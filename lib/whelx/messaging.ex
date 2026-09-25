defmodule Whelx.Messaging do
  @moduledoc "Conversations and messages between business numbers and fake contacts."

  import Ecto.Query
  alias Whelx.{Accounts, Contacts, Events, Ids, Repo, Templates, Webhooks}
  alias Whelx.Accounts.PhoneNumber
  alias Whelx.Graph.Error
  alias Whelx.Messaging.{Conversation, Message, StatusLifecycle, Throughput}
  alias Whelx.Webhooks.Payload

  @window_hours 24

  # Conversations

  @spec get_or_create_conversation(String.t(), String.t()) :: Conversation.t()
  def get_or_create_conversation(phone_number_id, wa_id) do
    case Repo.get_by(Conversation, phone_number_id: phone_number_id, contact_wa_id: wa_id) do
      nil ->
        %Conversation{phone_number_id: phone_number_id, contact_wa_id: wa_id}
        |> Repo.insert!(
          on_conflict: :nothing,
          conflict_target: [:phone_number_id, :contact_wa_id]
        )
        |> case do
          %Conversation{id: nil} ->
            Repo.get_by!(Conversation, phone_number_id: phone_number_id, contact_wa_id: wa_id)

          conversation ->
            conversation
        end

      conversation ->
        conversation
    end
  end

  def get_conversation!(id) do
    Conversation |> Repo.get!(id) |> Repo.preload([:contact, :messages])
  end

  def list_conversations(phone_number_id) do
    Repo.all(
      from c in Conversation,
        where: c.phone_number_id == ^phone_number_id,
        order_by: [desc_nulls_last: c.last_message_at, desc: c.id],
        preload: [:contact]
    )
  end

  @doc "Last message of each conversation, keyed by conversation id."
  def last_messages([]), do: %{}

  def last_messages(conversation_ids) do
    last_ids =
      from m in Message,
        where: m.conversation_id in ^conversation_ids,
        group_by: m.conversation_id,
        select: max(m.id)

    Repo.all(from m in Message, where: m.id in subquery(last_ids))
    |> Map.new(&{&1.conversation_id, &1})
  end

  @spec window_open?(Conversation.t(), DateTime.t()) :: boolean()
  def window_open?(conversation, now \\ DateTime.utc_now())
  def window_open?(%Conversation{window_expires_at: nil}, _now), do: false
  def window_open?(%Conversation{window_expires_at: at}, now), do: DateTime.after?(at, now)

  def expire_window(%Conversation{} = conversation) do
    conversation
    |> Ecto.Changeset.change(window_expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
    |> Repo.update()
    |> tap(fn _ -> broadcast_conversation(conversation.id) end)
  end

  # Inbound

  @doc """
  A contact sends a message to a business number. Renews the 24h window and
  queues the `messages` webhook.
  """
  def receive_inbound(phone_number_id, wa_id, %{type: type, content: content} = attrs) do
    phone = Accounts.get_phone_number!(phone_number_id)
    contact = Contacts.find_or_create_contact(wa_id)
    conversation = get_or_create_conversation(phone.id, contact.wa_id)
    now = DateTime.utc_now()

    {:ok, message} =
      Repo.transaction(fn ->
        message =
          Repo.insert!(%Message{
            wamid: Ids.wamid(),
            conversation_id: conversation.id,
            direction: "inbound",
            type: type,
            payload: %{"content" => content},
            status: "received",
            context_wamid: attrs[:context_wamid]
          })

        conversation
        |> Ecto.Changeset.change(
          window_expires_at: DateTime.add(now, @window_hours, :hour),
          last_message_at: now
        )
        |> Repo.update!()

        message
      end)

    {:ok, _} =
      Webhooks.enqueue(phone.waba_id, "messages", Payload.inbound(message, phone, contact),
        message_wamid: message.wamid
      )

    broadcast_message(:message_created, message)
    broadcast_conversation(conversation.id)
    {:ok, message}
  end

  @doc "A contact sends an attachment (image, audio, video, document, sticker)."
  def receive_inbound_media(phone_number_id, wa_id, type, binary, mime_type, opts \\ [])
      when type in ~w(image audio video document sticker) do
    {:ok, media} = Whelx.Media.store(binary, mime_type, opts[:file_name])

    content =
      %{
        "mime_type" => mime_type,
        "sha256" => media.sha256,
        "id" => media.id,
        "url" => Whelx.Media.url(media)
      }
      |> put_present("caption", opts[:caption])
      |> put_present("filename", if(type == "document", do: opts[:file_name]))
      |> then(fn c ->
        if type == "audio", do: Map.put(c, "voice", Keyword.get(opts, :voice, true)), else: c
      end)

    receive_inbound(phone_number_id, wa_id, %{
      type: type,
      content: content,
      context_wamid: opts[:context_wamid]
    })
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  # Outbound

  @doc """
  The business sends a message (already validated by `Graph.Validation`).
  Returns Meta's synchronous errors (130429, 132000, 132001) and otherwise
  accepts the message, deciding up front if it will fail asynchronously.
  """
  def send_outbound(%PhoneNumber{} = phone, %{kind: :message} = request) do
    with :ok <- throughput(phone),
         {:ok, extra} <- prepare(phone, request) do
      contact = Contacts.find_or_create_contact(request.to)
      conversation = get_or_create_conversation(phone.id, contact.wa_id)
      now = DateTime.utc_now()
      {failure, chaos_tag} = decide_failure(request, contact, conversation)

      {:ok, message} =
        Repo.transaction(fn ->
          message =
            Repo.insert!(%Message{
              wamid: Ids.wamid(),
              conversation_id: conversation.id,
              direction: "outbound",
              type: request.type,
              payload:
                extra
                |> Map.put("content", request.content)
                |> Map.put("pricing", pricing(extra["category"], window_open?(conversation))),
              status: "accepted",
              context_wamid: request.context_wamid,
              planned_failure: failure,
              chaos_tag: chaos_tag
            })

          from(c in Conversation, where: c.id == ^conversation.id)
          |> Repo.update_all(
            set: [last_message_at: now, typing_until: nil],
            inc: [unread_count: 1]
          )

          message
        end)

      after_accept(message)
      broadcast_message(:message_created, message)
      broadcast_conversation(conversation.id)
      {:ok, message}
    end
  end

  defp after_accept(message), do: StatusLifecycle.start(message)

  # PMP pricing as reported in status webhooks.
  defp pricing("service", _window_open?), do: free_pricing("service")
  defp pricing("utility", true), do: free_pricing("utility")

  defp pricing(category, _window_open?),
    do: %{
      "billable" => true,
      "pricing_model" => "PMP",
      "type" => "regular",
      "category" => category
    }

  defp free_pricing(category),
    do: %{
      "billable" => false,
      "pricing_model" => "PMP",
      "type" => "free_customer_service",
      "category" => category
    }

  # Status transitions

  @rank %{"accepted" => 0, "sent" => 1, "delivered" => 2, "read" => 3}

  @spec allowed_transition?(String.t(), String.t()) :: boolean()
  def allowed_transition?(from, "failed"), do: from in ~w(accepted sent)

  def allowed_transition?(from, to) do
    Map.has_key?(@rank, from) and Map.has_key?(@rank, to) and @rank[to] > @rank[from]
  end

  @doc "Moves an outbound message to `status` and queues its status webhook."
  def transition(message_id, status, opts \\ []) do
    case Repo.get(Message, message_id) do
      nil ->
        {:skip, :not_found}

      message ->
        if allowed_transition?(message.status, status),
          do: do_transition(message, status, opts),
          else: {:skip, :invalid_transition}
    end
  end

  defp do_transition(message, status, opts) do
    now = DateTime.utc_now()

    changes =
      [status: status]
      |> Keyword.put(timestamp_field(status), now)
      |> then(fn changes ->
        if status == "failed",
          do: Keyword.put(changes, :errors, [failure_error(message)]),
          else: changes
      end)

    message =
      message
      |> Ecto.Changeset.change(changes)
      |> Repo.update!()
      |> Repo.preload(conversation: :contact)

    conversation = message.conversation
    phone = Accounts.get_phone_number!(conversation.phone_number_id)

    {:ok, _} =
      Webhooks.enqueue(
        phone.waba_id,
        "statuses",
        Payload.status(message, phone, conversation.contact),
        Keyword.put(opts, :message_wamid, message.wamid)
      )

    broadcast_message(:message_updated, message)
    broadcast_conversation(conversation.id)
    {:ok, message}
  end

  defp timestamp_field("sent"), do: :sent_at
  defp timestamp_field("delivered"), do: :delivered_at
  defp timestamp_field("read"), do: :read_at
  defp timestamp_field("failed"), do: :failed_at

  defp failure_error(%Message{planned_failure: %{"code" => code} = failure}) do
    opts = if failure["details"], do: [details: failure["details"]], else: []
    Error.async(code, opts)
  end

  defp failure_error(_message), do: Error.async(131_000)

  @doc "The contact opens the chat: clears unread and reads delivered messages (read_policy on_open)."
  def open_conversation(conversation_id) do
    conversation = Conversation |> Repo.get!(conversation_id) |> Repo.preload(:contact)

    if conversation.unread_count > 0 do
      from(c in Conversation, where: c.id == ^conversation.id)
      |> Repo.update_all(set: [unread_count: 0])

      broadcast_conversation(conversation.id)
    end

    if conversation.contact.read_policy == "on_open" do
      from(m in Message,
        where:
          m.conversation_id == ^conversation.id and m.direction == "outbound" and
            m.status == "delivered",
        select: m.id
      )
      |> Repo.all()
      |> Enum.each(&transition(&1, "read"))
    end

    :ok
  end

  @doc "Toggles contact presence; coming online delivers messages held at `sent`."
  def set_contact_online(contact, online?) do
    with {:ok, contact} <- Contacts.update_contact(contact, %{online: online?}) do
      if online? do
        delay = Accounts.get_settings().delivered_delay_ms

        from(m in Message,
          join: c in assoc(m, :conversation),
          where:
            c.contact_wa_id == ^contact.wa_id and m.direction == "outbound" and m.status == "sent"
        )
        |> Repo.all()
        |> Enum.each(&StatusLifecycle.schedule(&1, "delivered", delay))
      end

      {:ok, contact}
    end
  end

  defp throughput(phone) do
    case Throughput.check(phone.id, phone.throughput_mps) do
      :ok ->
        :ok

      {:error, :rate_limited} ->
        {:error,
         Error.new(130_429,
           details:
             "Message failed to send because there were too many messages sent from this phone number in a short period of time"
         )}
    end
  end

  defp prepare(phone, %{type: "template", content: content}) do
    name = content["name"]
    language = get_in(content, ["language", "code"])
    components = content["components"] || []

    with {:ok, template} <- Templates.find_approved(phone.waba_id, name, language),
         :ok <- Templates.check_params(template, components) do
      {:ok,
       %{
         "rendered" => Templates.render(template, components),
         "category" => String.downcase(template.category)
       }}
    end
  end

  defp prepare(_phone, _request), do: {:ok, %{"category" => "service"}}

  defp decide_failure(request, contact, conversation) do
    case planned_failure(request, contact, conversation) do
      nil ->
        profile = Whelx.Chaos.get_profile()

        if Whelx.Chaos.hit?(profile, :async_fail, profile.async_fail_rate) do
          code = Whelx.Chaos.pick(profile, :async_fail_code, profile.async_fail_codes) || 131_000
          {%{"code" => code, "chaos" => true}, "async_fail:#{code}"}
        else
          {nil, nil}
        end

      failure ->
        {failure, nil}
    end
  end

  defp planned_failure(request, contact, conversation) do
    cond do
      contact.behavior == "invalid_number" ->
        %{"code" => 131_026}

      contact.behavior == "blocked" ->
        %{
          "code" => 131_026,
          "details" => "Unable to deliver message. The recipient has blocked this business."
        }

      request.type in ~w(text interactive) and not window_open?(conversation) ->
        %{"code" => 131_047}

      true ->
        nil
    end
  end

  @doc "Read receipt from the business; optional typing indicator (25 s)."
  def mark_read_by_business(phone_number_id, wamid, typing?) do
    message =
      Repo.one(
        from m in Message,
          join: c in assoc(m, :conversation),
          where:
            m.wamid == ^wamid and m.direction == "inbound" and
              c.phone_number_id == ^phone_number_id
      )

    case message do
      nil ->
        {:error,
         Error.invalid_parameter("message_id #{wamid} não encontrado nesta linha",
           details: "Invalid message id"
         )}

      message ->
        now = DateTime.utc_now()

        from(m in Message,
          where:
            m.conversation_id == ^message.conversation_id and m.direction == "inbound" and
              m.id <= ^message.id and m.status != "read"
        )
        |> Repo.update_all(set: [status: "read", read_at: now, updated_at: now])

        if typing? do
          from(c in Conversation, where: c.id == ^message.conversation_id)
          |> Repo.update_all(set: [typing_until: DateTime.add(now, 25, :second)])
        end

        message = Repo.get!(Message, message.id)
        broadcast_message(:message_updated, message)
        broadcast_conversation(message.conversation_id)
        {:ok, message}
    end
  end

  # Queries

  def get_message_by_wamid(wamid) do
    Message |> Repo.get_by(wamid: wamid) |> Repo.preload(conversation: :contact)
  end

  def list_messages(filters \\ %{}) do
    filters = Whelx.Attrs.stringify(filters)
    limit = parse_int(filters["limit"], 100)

    from(m in Message,
      join: c in assoc(m, :conversation),
      order_by: [desc: m.id],
      limit: ^limit,
      preload: [conversation: c]
    )
    |> filter_contact(filters["contact"])
    |> filter_eq(:direction, filters["direction"])
    |> filter_eq(:type, filters["type"])
    |> filter_eq(:status, filters["status"])
    |> filter_phone(filters["phone_number_id"])
    |> filter_after(filters["after_id"])
    |> Repo.all()
  end

  defp filter_contact(query, nil), do: query

  defp filter_contact(query, wa_id),
    do: where(query, [_m, c], c.contact_wa_id == ^Whelx.Attrs.digits(wa_id))

  defp filter_phone(query, nil), do: query
  defp filter_phone(query, id), do: where(query, [_m, c], c.phone_number_id == ^to_string(id))

  defp filter_eq(query, _field, nil), do: query
  defp filter_eq(query, field, value), do: where(query, [m], field(m, ^field) == ^value)

  defp filter_after(query, nil), do: query
  defp filter_after(query, id), do: where(query, [m], m.id > ^parse_int(id, 0))

  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      :error -> default
    end
  end

  @doc "Outbound template messages since `since`, grouped by template name."
  def campaign_stats(%DateTime{} = since) do
    from(m in Message,
      where: m.direction == "outbound" and m.type == "template" and m.inserted_at >= ^since,
      group_by: fragment("json_extract(?, '$.content.name')", m.payload),
      order_by: [desc: count(m.id)],
      select: %{
        name: fragment("json_extract(?, '$.content.name')", m.payload),
        total: count(m.id),
        accepted: sum(fragment("CASE WHEN ? = 'accepted' THEN 1 ELSE 0 END", m.status)),
        sent: sum(fragment("CASE WHEN ? = 'sent' THEN 1 ELSE 0 END", m.status)),
        delivered: sum(fragment("CASE WHEN ? = 'delivered' THEN 1 ELSE 0 END", m.status)),
        read: sum(fragment("CASE WHEN ? = 'read' THEN 1 ELSE 0 END", m.status)),
        failed: sum(fragment("CASE WHEN ? = 'failed' THEN 1 ELSE 0 END", m.status)),
        first_at: min(m.inserted_at),
        last_at: max(m.inserted_at)
      }
    )
    |> Repo.all()
  end

  # Events

  @doc false
  def broadcast_message(event, %Message{} = message),
    do: Events.broadcast("messages", {event, message})

  @doc false
  def broadcast_conversation(id),
    do: Events.broadcast("conversations", {:conversation_updated, id})
end
