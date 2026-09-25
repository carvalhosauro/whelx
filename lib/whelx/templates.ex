defmodule Whelx.Templates do
  @moduledoc "Message templates: creation, review, lookup for sending and rendering."

  import Ecto.Query
  alias Whelx.{Accounts, Attrs, Events, Ids, Repo}
  alias Whelx.Graph.{Error, Validation}
  alias Whelx.Graph.Validation.TemplateDefinition
  alias Whelx.Templates.{ReviewWorker, Template}

  @var ~r/\{\{(\d+)\}\}/

  def get_template(id), do: Repo.get(Template, to_string(id))

  def list_all(waba_id \\ nil) do
    Template
    |> order_by([t], asc: t.inserted_at, asc: t.id)
    |> then(fn q -> if waba_id, do: where(q, [t], t.waba_id == ^waba_id), else: q end)
    |> Repo.all()
  end

  @doc "Graph-style creation: validates, starts PENDING and applies the approval policy."
  def create_template(waba_id, params) do
    params = Attrs.stringify(params)

    with :ok <- Validation.validate_template_definition(params),
         :ok <- check_header_handles(params["components"]),
         :ok <- ensure_unique(waba_id, params) do
      {:ok, template} =
        %Template{}
        |> Template.changeset(%{
          id: Ids.numeric_id(),
          waba_id: waba_id,
          name: params["name"],
          language: params["language"],
          category: String.upcase(params["category"]),
          components: normalize(params["components"]),
          status: "PENDING"
        })
        |> Repo.insert()

      schedule_review(template, Accounts.get_settings())
      broadcast({:ok, template})
    end
  end

  @doc "Upsert used by seeding. Status defaults to APPROVED."
  def seed_template(waba_id, params) do
    params = Attrs.stringify(params)

    with :ok <- Validation.validate_template_definition(params) do
      existing =
        Repo.get_by(Template,
          waba_id: waba_id,
          name: params["name"],
          language: params["language"]
        )

      (existing || %Template{id: params["id"] || Ids.numeric_id()})
      |> Template.changeset(%{
        waba_id: waba_id,
        name: params["name"],
        language: params["language"],
        category: String.upcase(params["category"]),
        components: normalize(params["components"]),
        status: params["status"] || "APPROVED",
        rejected_reason: params["rejected_reason"]
      })
      |> Repo.insert_or_update()
      |> broadcast()
    end
  end

  def approve(%Template{} = t),
    do:
      t
      |> Ecto.Changeset.change(status: "APPROVED", rejected_reason: nil)
      |> Repo.update()
      |> broadcast()

  def reject(%Template{} = t, reason),
    do:
      t
      |> Ecto.Changeset.change(status: "REJECTED", rejected_reason: reason)
      |> Repo.update()
      |> broadcast()

  def delete_by_name(waba_id, name) do
    case Repo.delete_all(from t in Template, where: t.waba_id == ^waba_id and t.name == ^name) do
      {0, _} ->
        {:error, Error.invalid_parameter("template #{name} não encontrado", subcode: 2_593_002)}

      {count, _} ->
        broadcast({:ok, count})
    end
  end

  @doc "Cursor-paginated list with optional `name` (substring) and `status` filters."
  def list_templates(waba_id, opts \\ %{}) do
    opts = Attrs.stringify(opts)
    limit = opts["limit"] |> to_int(25) |> max(1) |> min(1000)
    offset = decode_cursor(opts["after"])

    rows =
      from(t in Template, where: t.waba_id == ^waba_id, order_by: [asc: t.inserted_at, asc: t.id])
      |> filter_name(opts["name"])
      |> filter_status(opts["status"])
      |> limit(^(limit + 1))
      |> offset(^offset)
      |> Repo.all()

    {page, rest} = Enum.split(rows, limit)

    %{
      data: page,
      before: encode_cursor(offset),
      after: if(rest != [], do: encode_cursor(offset + limit))
    }
  end

  @doc "Template ready to send, or Meta's 132001."
  def find_approved(waba_id, name, language) do
    case Repo.get_by(Template, waba_id: waba_id, name: name, language: language) do
      %Template{status: "APPROVED"} = t ->
        {:ok, t}

      %Template{status: status} ->
        {:error,
         Error.new(132_001, details: "template name (#{name}) in #{language} is #{status}")}

      nil ->
        {:error,
         Error.new(132_001, details: "template name (#{name}) does not exist in #{language}")}
    end
  end

  @doc "Meta's 132000 when the number of body/header text parameters doesn't match."
  def check_params(%Template{} = t, sent) do
    sent = sent || []

    checks =
      [{"BODY", "body"}] ++
        if match?(%{"format" => "TEXT"}, find(t.components, "HEADER")),
          do: [{"HEADER", "header"}],
          else: []

    Enum.reduce_while(checks, :ok, fn {def_type, sent_type}, :ok ->
      expected = t.components |> find(def_type) |> text() |> variable_count()
      given = sent |> params_for(sent_type) |> length()

      if expected == given do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Error.new(132_000,
            details:
              "#{sent_type}: number of localizable_params (#{given}) does not match the expected number of params (#{expected})"
          )}}
      end
    end)
  end

  @doc "Rendered view (header/body/footer/buttons) with parameters applied."
  def render(%Template{} = t, sent) do
    sent = sent || []

    %{
      "name" => t.name,
      "language" => t.language,
      "category" => t.category,
      "header" => render_header(find(t.components, "HEADER"), params_for(sent, "header")),
      "body" => fill(text(find(t.components, "BODY")), params_for(sent, "body")),
      "footer" => text(find(t.components, "FOOTER")),
      "buttons" => render_buttons(find(t.components, "BUTTONS"), sent)
    }
  end

  @doc "Graph JSON with `fields` selection."
  def to_graph(%Template{} = t, fields) do
    full = %{
      "id" => t.id,
      "name" => t.name,
      "language" => t.language,
      "status" => t.status,
      "category" => t.category,
      "components" => t.components,
      "parameter_format" => "POSITIONAL"
    }

    full =
      if t.rejected_reason, do: Map.put(full, "rejected_reason", t.rejected_reason), else: full

    Whelx.Graph.Fields.select(full, fields, ~w(name components language status category))
  end

  def variable_count(nil), do: 0

  def variable_count(text) do
    @var |> Regex.scan(text, capture: :all_but_first) |> List.flatten() |> Enum.uniq() |> length()
  end

  defp ensure_unique(waba_id, params) do
    if Repo.exists?(
         from t in Template,
           where:
             t.waba_id == ^waba_id and t.name == ^params["name"] and
               t.language == ^params["language"]
       ) do
      {:error,
       Error.invalid_parameter(
         "Já existe conteúdo para #{params["name"]} em #{params["language"]}.",
         subcode: 2_388_024,
         user_title: "Content in This Language Already Exists"
       )}
    else
      :ok
    end
  end

  defp check_header_handles(components) do
    handles =
      for c <- components,
          TemplateDefinition.type_of(c) == "HEADER",
          handle <- List.wrap(get_in(c, ["example", "header_handle"])),
          do: handle

    case Enum.reject(handles, &Whelx.Media.handle_exists?/1) do
      [] ->
        :ok

      [bad | _] ->
        {:error,
         Error.invalid_parameter(
           "example.header_handle #{bad} não foi enviado via upload resumable",
           subcode: 2_494_102
         )}
    end
  end

  defp schedule_review(_template, %{template_approval_policy: "manual"}), do: :ok

  defp schedule_review(template, settings) do
    decision =
      if settings.template_approval_policy == "auto_approve", do: "approve", else: "reject"

    at = DateTime.add(DateTime.utc_now(), settings.template_review_after_ms, :millisecond)

    %{"template_id" => template.id, "decision" => decision}
    |> ReviewWorker.new(scheduled_at: at)
    |> Oban.insert!()

    :ok
  end

  defp normalize(components) do
    Enum.map(components, fn component ->
      component
      |> Map.put("type", TemplateDefinition.type_of(component))
      |> then(fn c ->
        if c["format"], do: Map.put(c, "format", String.upcase(c["format"])), else: c
      end)
    end)
  end

  defp find(components, type),
    do: Enum.find(components || [], &(TemplateDefinition.type_of(&1) == type))

  defp text(nil), do: nil
  defp text(component), do: component["text"]

  defp params_for(sent, type) do
    case Enum.find(sent, &(&1["type"] == type)) do
      nil -> []
      component -> component["parameters"] || []
    end
  end

  defp fill(nil, _params), do: nil

  defp fill(text, params) do
    Regex.replace(@var, text, fn whole, n ->
      case Enum.at(params, String.to_integer(n) - 1) do
        nil -> whole
        param -> param_text(param)
      end
    end)
  end

  defp param_text(%{"type" => "text", "text" => text}), do: text
  defp param_text(%{"type" => "currency", "currency" => %{"fallback_value" => v}}), do: v
  defp param_text(%{"type" => "date_time", "date_time" => %{"fallback_value" => v}}), do: v
  defp param_text(other), do: Jason.encode!(other)

  defp render_header(nil, _params), do: nil

  defp render_header(%{"format" => "TEXT"} = c, params),
    do: %{"format" => "TEXT", "text" => fill(c["text"], params)}

  defp render_header(%{"format" => format}, params) do
    media = Enum.find_value(params, fn p -> p[String.downcase(format)] end) || %{}

    %{
      "format" => format,
      "link" => media["link"],
      "id" => media["id"],
      "filename" => media["filename"]
    }
  end

  defp render_buttons(nil, _sent), do: []

  defp render_buttons(%{"buttons" => buttons}, sent) do
    sent_buttons =
      for %{"type" => "button"} = b <- sent, into: %{}, do: {to_string(b["index"]), b}

    buttons
    |> Enum.with_index()
    |> Enum.map(fn {button, index} ->
      index = Integer.to_string(index)
      type = String.upcase(button["type"])
      sent_params = get_in(sent_buttons, [index, "parameters"]) || []

      %{"index" => index, "type" => type, "text" => button["text"]}
      |> put_button_extra(type, button, sent_params)
    end)
  end

  defp put_button_extra(map, "QUICK_REPLY", _button, params),
    do: Map.put(map, "payload", Enum.find_value(params, & &1["payload"]))

  defp put_button_extra(map, "URL", button, params),
    do: Map.put(map, "url", fill(button["url"], params))

  defp put_button_extra(map, _type, button, _params),
    do: Map.merge(map, Map.take(button, ["phone_number", "example"]))

  defp filter_name(query, blank) when blank in [nil, ""], do: query
  defp filter_name(query, name), do: where(query, [t], like(t.name, ^"%#{name}%"))

  defp filter_status(query, blank) when blank in [nil, ""], do: query
  defp filter_status(query, status), do: where(query, [t], t.status == ^String.upcase(status))

  defp encode_cursor(offset), do: Base.url_encode64("o:#{offset}", padding: false)

  defp decode_cursor(nil), do: 0

  defp decode_cursor(cursor) do
    with {:ok, "o:" <> n} <- Base.url_decode64(cursor, padding: false),
         {int, ""} <- Integer.parse(n) do
      int
    else
      _ -> 0
    end
  end

  defp to_int(nil, default), do: default
  defp to_int(v, _default) when is_integer(v), do: v

  defp to_int(v, default) do
    case Integer.parse(to_string(v)) do
      {int, _} -> int
      :error -> default
    end
  end

  defp broadcast({:ok, value} = result) do
    Events.broadcast("templates", {:templates_changed, value})
    result
  end

  defp broadcast(other), do: other
end
