defmodule Whelx.Control do
  @moduledoc """
  Operations behind the REST control API, the MCP tools and the UI:
  seeding, reset, acting as a contact and inspecting configuration.
  """

  import Ecto.Query
  alias Whelx.{Accounts, Attrs, Chaos, Contacts, Events, Media, Messaging, Repo, Templates}
  alias Whelx.Control.JSON
  alias Whelx.Messaging.{Conversation, Message, Throughput}

  @doc """
  Declarative, idempotent scenario setup. Keys (all optional): `app`, `wabas`
  (with nested `phone_numbers`), `tokens` (`wabas`: list or `"all"`),
  `contacts`, `templates` (status defaults to APPROVED), `settings`, `chaos`.
  """
  def seed(params) do
    params = Attrs.stringify(params)

    Repo.transaction(fn ->
      if app = params["app"], do: ok!(Accounts.upsert_app(rename(app, "app_id", "id")))

      for w <- params["wabas"] || [] do
        waba = ok!(Accounts.upsert_waba(Map.drop(w, ["phone_numbers"])))

        for p <- w["phone_numbers"] || [],
            do: ok!(Accounts.upsert_phone_number(Map.put(p, "waba_id", waba.id)))
      end

      for t <- params["tokens"] || [] do
        ok!(
          Accounts.upsert_token(%{
            "token" => t["token"],
            "waba_ids" => token_wabas(t["wabas"] || t["waba_ids"]),
            "expires_at" => t["expires_at"]
          })
        )
      end

      for c <- params["contacts"] || [], do: ok!(upsert_contact(c))
      for t <- params["templates"] || [], do: ok!(Templates.seed_template(t["waba_id"], t))
      if s = params["settings"], do: ok!(Accounts.update_settings(s))
      if c = params["chaos"], do: ok!(Chaos.update_profile(c))
      :ok
    end)
    |> case do
      {:ok, :ok} -> {:ok, snapshot()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rename(map, from, to) do
    case Map.pop(map, from) do
      {nil, map} -> map
      {value, map} -> Map.put(map, to, value)
    end
  end

  defp token_wabas("all"), do: Enum.map(Accounts.list_wabas(), & &1.id)
  defp token_wabas(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp token_wabas(_), do: []

  defp upsert_contact(attrs) do
    case attrs["wa_id"] && Contacts.get_contact(attrs["wa_id"]) do
      nil -> Contacts.create_contact(attrs)
      contact -> Contacts.update_contact(contact, attrs)
    end
  end

  defp ok!({:ok, value}), do: value
  defp ok!({:error, %Ecto.Changeset{} = cs}), do: Repo.rollback(changeset_errors(cs))
  defp ok!({:error, %Whelx.Graph.Error{} = e}), do: Repo.rollback(e.user_msg || e.message)
  defp ok!({:error, reason}), do: Repo.rollback(reason)

  @doc false
  def changeset_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", inspect(v)) end)
    end)
  end

  @doc "Current configuration (survives reset)."
  def snapshot do
    %{
      "app" => (app = Accounts.get_app()) && JSON.app(app),
      "wabas" =>
        Enum.map(Accounts.list_wabas(), &JSON.waba(&1, Accounts.list_phone_numbers(&1.id))),
      "tokens" => Enum.map(Accounts.list_tokens(), &JSON.token/1),
      "settings" => JSON.settings(Accounts.get_settings()),
      "chaos" => JSON.chaos(Chaos.get_profile()),
      "public_url" => Whelx.public_url()
    }
  end

  @doc "Environment block for pigz-api's .env."
  def env_block do
    app = Accounts.get_app!()

    """
    META_APP_ID=#{app.id}
    META_APP_SECRET=#{app.app_secret}
    META_GRAPH_BASE_URL=#{Whelx.public_url()}
    META_GRAPH_API_VERSION=v25.0
    WHATSAPP_WEBHOOK_VERIFY_TOKEN=#{app.verify_token}
    """
  end

  @doc "Removes test data. `keep` may contain \"contacts\" and/or \"templates\"."
  def reset(keep \\ []) do
    keep = MapSet.new(keep)

    jobs =
      from(j in Oban.Job, where: j.state in ["available", "scheduled", "retryable", "executing"])

    jobs =
      if MapSet.member?(keep, "templates"),
        do: where(jobs, [j], j.worker != "Whelx.Templates.ReviewWorker"),
        else: jobs

    Oban.cancel_all_jobs(jobs)

    Repo.transaction(fn ->
      Repo.delete_all(Whelx.Webhooks.Delivery)
      Repo.delete_all(Whelx.Logs.GraphRequest)
      Repo.delete_all(Message)
      Repo.delete_all(Conversation)

      if MapSet.member?(keep, "templates") do
        header_media =
          from(s in Media.UploadSession, where: not is_nil(s.media_id), select: s.media_id)

        Repo.delete_all(from m in Media.MediaFile, where: m.id not in subquery(header_media))
      else
        Repo.delete_all(Templates.Template)
        Repo.delete_all(Media.UploadSession)
        Repo.delete_all(Media.MediaFile)
      end

      unless MapSet.member?(keep, "contacts"), do: Repo.delete_all(Contacts.Contact)
    end)

    Media.prune_orphan_files()
    Chaos.reset_counters()
    Throughput.reset()
    Whelx.Messaging.PairLimit.reset()
    Events.broadcast("config", :reset)
    :ok
  end

  def default_phone_id do
    case Accounts.list_all_phone_numbers() do
      [phone | _] -> {:ok, phone.id}
      [] -> {:error, "nenhum número configurado"}
    end
  end

  @doc "A contact sends a message to a business number."
  def send_as_contact(wa_id, attrs) do
    attrs = Attrs.stringify(attrs)

    with :ok <- valid_wa_id(wa_id),
         {:ok, phone_id} <- phone_id(attrs) do
      context = attrs["context_wamid"]

      case attrs["type"] do
        "text" ->
          inbound(phone_id, wa_id, "text", %{"body" => to_string(attrs["text"])}, context)

        "reaction" ->
          inbound(phone_id, wa_id, "reaction", Map.take(attrs, ["message_id", "emoji"]), nil)

        "location" ->
          inbound(
            phone_id,
            wa_id,
            "location",
            Map.take(attrs, ["latitude", "longitude", "name", "address", "url"]),
            context
          )

        type when type in ~w(image audio video document) ->
          media(phone_id, wa_id, type, attrs)

        type ->
          {:error, "tipo não suportado: #{type}"}
      end
    end
  end

  defp valid_wa_id(wa_id) do
    if String.length(Attrs.digits(wa_id)) in 8..15,
      do: :ok,
      else: {:error, "wa_id inválido: #{inspect(wa_id)} (8 a 15 dígitos)"}
  end

  defp phone_id(%{"phone_number_id" => id}) when is_binary(id) and id != "" do
    if Accounts.get_phone_number(id),
      do: {:ok, id},
      else: {:error, "phone_number_id #{id} não existe"}
  end

  defp phone_id(_attrs), do: default_phone_id()

  defp inbound(phone_id, wa_id, type, content, context) do
    Messaging.receive_inbound(phone_id, wa_id, %{
      type: type,
      content: content,
      context_wamid: context
    })
  end

  defp media(phone_id, wa_id, type, attrs) do
    case Base.decode64(to_string(attrs["media_base64"])) do
      {:ok, binary} when binary != "" ->
        Messaging.receive_inbound_media(
          phone_id,
          wa_id,
          type,
          binary,
          attrs["mime_type"] || default_mime(type),
          caption: attrs["caption"],
          file_name: attrs["file_name"],
          context_wamid: attrs["context_wamid"]
        )

      _ ->
        {:error, "media_base64 inválido"}
    end
  end

  defp default_mime("audio"), do: "audio/ogg; codecs=opus"
  defp default_mime("image"), do: "image/jpeg"
  defp default_mime("video"), do: "video/mp4"
  defp default_mime("document"), do: "application/pdf"

  @doc "The contact taps a reply button, list row or template quick reply."
  def reply_interactive(wa_id, wamid, reply_id) do
    with {:ok, message} <- fetch_outbound(wamid),
         :ok <- same_contact(message, wa_id),
         {:ok, type, content} <- reply_content(message, to_string(reply_id)) do
      conversation = message.conversation

      inbound(
        conversation.phone_number_id,
        conversation.contact_wa_id,
        type,
        content,
        message.wamid
      )
    end
  end

  defp fetch_outbound(wamid) do
    case Messaging.get_message_by_wamid(wamid) do
      %Message{direction: "outbound"} = message -> {:ok, message}
      %Message{} -> {:error, "a mensagem #{wamid} não foi enviada pelo business"}
      nil -> {:error, :not_found}
    end
  end

  defp same_contact(message, wa_id) do
    if message.conversation.contact_wa_id == Attrs.digits(wa_id),
      do: :ok,
      else: {:error, "a mensagem não pertence ao contato #{wa_id}"}
  end

  defp reply_content(%Message{type: "interactive"} = message, id) do
    content = Message.content(message)

    case content["type"] do
      "button" ->
        case Enum.find(
               get_in(content, ["action", "buttons"]) || [],
               &(get_in(&1, ["reply", "id"]) == id)
             ) do
          nil ->
            {:error, "botão #{id} não existe"}

          button ->
            {:ok, "interactive",
             %{
               "type" => "button_reply",
               "button_reply" => %{"id" => id, "title" => button["reply"]["title"]}
             }}
        end

      "list" ->
        rows =
          content
          |> get_in(["action", "sections"])
          |> List.wrap()
          |> Enum.flat_map(&(&1["rows"] || []))

        case Enum.find(rows, &(&1["id"] == id)) do
          nil ->
            {:error, "linha #{id} não existe"}

          row ->
            reply = %{"id" => id, "title" => row["title"]}

            reply =
              if row["description"],
                do: Map.put(reply, "description", row["description"]),
                else: reply

            {:ok, "interactive", %{"type" => "list_reply", "list_reply" => reply}}
        end

      other ->
        {:error, "interactive #{other} não tem opções clicáveis"}
    end
  end

  defp reply_content(%Message{type: "template"} = message, id) do
    buttons = get_in(message.payload, ["rendered", "buttons"]) || []

    case Enum.find(
           buttons,
           &(&1["type"] == "QUICK_REPLY" and (&1["index"] == id or &1["payload"] == id))
         ) do
      nil ->
        {:error, "quick reply #{id} não existe"}

      button ->
        {:ok, "button",
         %{"payload" => button["payload"] || button["text"], "text" => button["text"]}}
    end
  end

  defp reply_content(_message, _id), do: {:error, "mensagem sem opções clicáveis"}
end
