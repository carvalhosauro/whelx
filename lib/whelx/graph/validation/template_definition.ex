defmodule Whelx.Graph.Validation.TemplateDefinition do
  @moduledoc "Rules for `POST /{waba_id}/message_templates`."

  import Whelx.Graph.Validation, only: [fail: 1, string: 2, max_len: 3, each: 2]

  @categories ~w(MARKETING UTILITY AUTHENTICATION)
  @formats ~w(TEXT IMAGE VIDEO DOCUMENT LOCATION)
  @button_types ~w(QUICK_REPLY URL PHONE_NUMBER COPY_CODE OTP FLOW)

  def validate(params) when is_map(params) do
    with {:ok, name} <- string(params, "name"),
         :ok <- name_format(name),
         {:ok, _language} <- string(params, "language"),
         {:ok, category} <- string(params, "category"),
         :ok <- category(category),
         {:ok, components} <- components(params["components"]),
         :ok <- body_count(components),
         do: each(components, &component/1)
  end

  def validate(_), do: fail("corpo inválido")

  @spec type_of(map()) :: String.t()
  def type_of(component), do: component["type"] |> to_string() |> String.upcase()

  defp name_format(name) do
    if Regex.match?(~r/^[a-z0-9_]{1,512}$/, name),
      do: :ok,
      else: fail("name deve conter apenas a-z, 0-9 e _ (recebido #{inspect(name)})")
  end

  defp category(category) do
    if String.upcase(category) in @categories,
      do: :ok,
      else: fail("category inválida: #{category}")
  end

  defp components(list) when is_list(list) and list != [], do: {:ok, list}
  defp components(_), do: fail("components deve ser uma lista não vazia")

  defp body_count(components) do
    if Enum.count(components, &(type_of(&1) == "BODY")) == 1,
      do: :ok,
      else: fail("components precisa de exatamente um BODY")
  end

  defp component(component) do
    case type_of(component) do
      "BODY" ->
        with {:ok, text} <- string(component, "text"),
             :ok <- max_len(text, 1024, "BODY.text"),
             do: variables(text, get_in(component, ["example", "body_text"]), "BODY")

      "HEADER" ->
        header(component)

      "FOOTER" ->
        with {:ok, text} <- string(component, "text"), do: max_len(text, 60, "FOOTER.text")

      "BUTTONS" ->
        buttons(component["buttons"])

      other ->
        fail("tipo de componente inválido: #{other}")
    end
  end

  defp header(component) do
    format = component["format"] |> to_string() |> String.upcase()

    cond do
      format not in @formats ->
        fail("HEADER.format inválido: #{inspect(component["format"])}")

      format == "TEXT" ->
        with {:ok, text} <- string(component, "text"),
             :ok <- max_len(text, 60, "HEADER.text"),
             do: variables(text, wrap(get_in(component, ["example", "header_text"])), "HEADER")

      format == "LOCATION" ->
        :ok

      true ->
        case get_in(component, ["example", "header_handle"]) do
          [handle | _] when is_binary(handle) -> :ok
          _ -> fail("HEADER #{format} exige example.header_handle")
        end
    end
  end

  defp wrap(nil), do: nil
  defp wrap(list) when is_list(list), do: [list]

  defp variables(text, examples, where) do
    vars =
      ~r/\{\{(\d+)\}\}/
      |> Regex.scan(text, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.to_integer/1)
      |> Enum.uniq()
      |> Enum.sort()

    cond do
      vars == [] ->
        :ok

      vars != Enum.to_list(1..length(vars)) ->
        fail("#{where}: variáveis devem ser sequenciais a partir de {{1}}")

      true ->
        case examples do
          [first | _] when is_list(first) and length(first) == length(vars) -> :ok
          _ -> fail("#{where}: example com #{length(vars)} valores é obrigatório")
        end
    end
  end

  defp buttons(list) when is_list(list) and length(list) in 1..10, do: each(list, &button/1)
  defp buttons(_), do: fail("BUTTONS deve ter de 1 a 10 botões")

  defp button(%{"type" => type} = button) do
    type = String.upcase(to_string(type))

    cond do
      type not in @button_types ->
        fail("tipo de botão inválido: #{type}")

      type == "URL" and not is_binary(button["url"]) ->
        fail("botão URL exige url")

      type == "PHONE_NUMBER" and not is_binary(button["phone_number"]) ->
        fail("botão PHONE_NUMBER exige phone_number")

      type in ~w(QUICK_REPLY URL PHONE_NUMBER) ->
        with {:ok, text} <- string(button, "text"), do: max_len(text, 25, "button.text")

      true ->
        :ok
    end
  end

  defp button(_), do: fail("tipo de botão ausente")
end
