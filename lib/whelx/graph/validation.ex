defmodule Whelx.Graph.Validation do
  @moduledoc """
  Validation of `POST /{phone_number_id}/messages` payloads and template
  definitions, limited to what pigz-api sends. Failures are Meta `code 100`
  errors with a descriptive `error_user_msg`.
  """

  alias Whelx.Attrs
  alias Whelx.Graph.Error
  alias Whelx.Graph.Validation.{Interactive, TemplateDefinition}

  @supported ~w(text template interactive)
  @known ~w(image audio video document sticker location contacts reaction)
  @button_sub_types ~w(quick_reply url copy_code flow order_details catalog voice_call)

  @type send_request ::
          %{
            kind: :message,
            to: String.t(),
            to_input: String.t(),
            type: String.t(),
            content: map(),
            context_wamid: String.t() | nil
          }
          | %{kind: :read, message_id: String.t(), typing: boolean()}

  @spec validate_send(map()) :: {:ok, send_request()} | {:error, Error.t()}
  def validate_send(%{"status" => "read"} = params) do
    with :ok <- messaging_product(params),
         {:ok, id} <- string(params, "message_id") do
      {:ok,
       %{
         kind: :read,
         message_id: id,
         typing: match?(%{"type" => "text"}, params["typing_indicator"])
       }}
    end
  end

  def validate_send(params) when is_map(params) do
    do_validate_send(params)
  rescue
    # Backstop: an unexpected shape must be Meta's code 100, never a whelx 500.
    _ in [
      FunctionClauseError,
      Protocol.UndefinedError,
      ArgumentError,
      BadMapError,
      CaseClauseError
    ] ->
      fail("corpo da requisição com formato inválido")
  end

  def validate_send(_params), do: fail("corpo da requisição inválido")

  defp do_validate_send(params) do
    with :ok <- messaging_product(params),
         :ok <- recipient_type(params),
         {:ok, to} <- recipient(params),
         {:ok, type} <- string(params, "type"),
         :ok <- supported(type),
         {:ok, content} <- content(params, type),
         :ok <- validate_content(type, content),
         {:ok, context_wamid} <- context(params["context"]) do
      {:ok,
       %{
         kind: :message,
         to: to,
         to_input: to_string(params["to"]),
         type: type,
         content: content,
         context_wamid: context_wamid
       }}
    end
  end

  defp context(nil), do: {:ok, nil}
  defp context(%{"message_id" => id}) when is_binary(id), do: {:ok, id}
  defp context(_), do: fail("context deve ser {message_id: \"wamid...\"}")

  @spec validate_template_definition(map()) :: :ok | {:error, Error.t()}
  def validate_template_definition(params), do: TemplateDefinition.validate(params)

  defp messaging_product(%{"messaging_product" => "whatsapp"}), do: :ok
  defp messaging_product(_), do: fail(~s(messaging_product deve ser "whatsapp"))

  defp recipient_type(%{"recipient_type" => rt}) when rt not in [nil, "individual"],
    do: fail(~s(recipient_type deve ser "individual"))

  defp recipient_type(_), do: :ok

  defp recipient(%{"to" => to}) when not (is_binary(to) or is_integer(to)),
    do: fail("to deve ser texto com o número")

  defp recipient(params) do
    digits = Attrs.digits(params["to"])

    if String.length(digits) in 8..15,
      do: {:ok, digits},
      else: fail("to inválido: #{inspect(params["to"])}")
  end

  defp supported(type) when type in @supported, do: :ok

  defp supported(type) when type in @known,
    do: {:error, Error.unsupported("envio de mensagem type=#{type}")}

  defp supported(type), do: fail("type desconhecido: #{type}")

  defp content(params, type) do
    case params[type] do
      map when is_map(map) -> {:ok, map}
      _ -> fail("objeto #{type} ausente")
    end
  end

  defp validate_content("text", content) do
    with {:ok, body} <- string(content, "body"),
         :ok <- max_len(body, 4096, "text.body") do
      if is_nil(content["preview_url"]) or is_boolean(content["preview_url"]),
        do: :ok,
        else: fail("text.preview_url deve ser booleano")
    end
  end

  defp validate_content("template", content) do
    with {:ok, _name} <- string(content, "name"),
         {:ok, _code} <- string(map_or_empty(content["language"]), "code") do
      template_components(content["components"])
    end
  end

  defp validate_content("interactive", content), do: Interactive.validate(content)

  defp template_components(nil), do: :ok

  defp template_components(list) when is_list(list) do
    each(list, fn
      %{"type" => type} = component when type in ~w(header body button footer) ->
        component_params(component)

      _ ->
        fail("template.components contém componente inválido")
    end)
  end

  defp template_components(_), do: fail("template.components deve ser uma lista")

  defp component_params(%{"type" => "button"} = component) do
    cond do
      component["sub_type"] not in @button_sub_types ->
        fail("button.sub_type inválido: #{inspect(component["sub_type"])}")

      is_nil(component["index"]) ->
        fail("button.index é obrigatório")

      true ->
        params_list(component["parameters"])
    end
  end

  defp component_params(component), do: params_list(component["parameters"])

  defp params_list(nil), do: :ok

  defp params_list(list) when is_list(list) do
    if Enum.all?(list, &match?(%{"type" => type} when is_binary(type), &1)),
      do: :ok,
      else: fail("parameters: cada item precisa de type")
  end

  defp params_list(_), do: fail("parameters deve ser uma lista")

  # Shared helpers (also used by the submodules)

  @doc false
  def map_or_empty(value) when is_map(value), do: value
  def map_or_empty(_value), do: %{}

  @doc false
  def fail(message), do: {:error, Error.invalid_parameter(message)}

  @doc false
  def string(map, key) when is_map(map) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> fail("#{key} é obrigatório")
    end
  end

  def string(_map, key), do: fail("#{key} é obrigatório")

  @doc false
  def max_len(value, max, field) do
    if String.length(value) <= max, do: :ok, else: fail("#{field} excede #{max} caracteres")
  end

  @doc false
  def each(list, fun) do
    Enum.reduce_while(list, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc false
  def http_url(value, field) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        :ok

      _ ->
        fail("#{field} deve ser uma URL http(s): #{inspect(value)}")
    end
  end
end
