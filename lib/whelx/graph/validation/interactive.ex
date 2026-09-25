defmodule Whelx.Graph.Validation.Interactive do
  @moduledoc "Rules for interactive `button`, `list`, `cta_url` and `order_details` messages."

  import Whelx.Graph.Validation, only: [fail: 1, string: 2, max_len: 3, each: 2, http_url: 2]
  alias Whelx.Graph.Error

  @key_types ~w(CPF CNPJ EMAIL PHONE EVP)

  def validate(%{"action" => action}) when not is_map(action),
    do: fail("interactive.action deve ser um objeto")

  def validate(%{"body" => body}) when not is_map(body),
    do: fail("interactive.body deve ser um objeto")

  def validate(i) when not is_map(i), do: fail("interactive deve ser um objeto")

  def validate(%{"type" => "button"} = i) do
    with :ok <- body(i), do: buttons(get_in(i, ["action", "buttons"]))
  end

  def validate(%{"type" => "list"} = i) do
    with :ok <- body(i),
         {:ok, label} <- string(i["action"] || %{}, "button"),
         :ok <- max_len(label, 20, "action.button"),
         do: sections(get_in(i, ["action", "sections"]))
  end

  def validate(%{"type" => "cta_url"} = i) do
    params = get_in(i, ["action", "parameters"]) || %{}

    with :ok <- body(i),
         :ok <- equal(get_in(i, ["action", "name"]), "cta_url", "action.name"),
         {:ok, text} <- string(params, "display_text"),
         :ok <- max_len(text, 20, "display_text"),
         {:ok, url} <- string(params, "url"),
         do: http_url(url, "url")
  end

  def validate(%{"type" => "order_details"} = i) do
    with :ok <- body(i),
         :ok <- equal(get_in(i, ["action", "name"]), "review_and_pay", "action.name"),
         do: order_parameters(get_in(i, ["action", "parameters"]))
  end

  def validate(%{"type" => type}) when is_binary(type),
    do: {:error, Error.unsupported("interactive.type=#{type}")}

  def validate(_), do: fail("interactive.type é obrigatório")

  defp body(i) do
    with {:ok, text} <- string(i["body"] || %{}, "text"), do: max_len(text, 1024, "body.text")
  end

  defp buttons(list) when is_list(list) and length(list) in 1..3 do
    ids = for %{"reply" => %{"id" => id}} <- list, do: id

    with :ok <- each(list, &button/1) do
      if length(Enum.uniq(ids)) == length(list),
        do: :ok,
        else: fail("action.buttons: ids duplicados")
    end
  end

  defp buttons(_), do: fail("action.buttons deve ter de 1 a 3 botões")

  defp button(%{"type" => "reply", "reply" => reply}) do
    with {:ok, id} <- string(reply, "id"),
         :ok <- max_len(id, 256, "reply.id"),
         {:ok, title} <- string(reply, "title"),
         do: max_len(title, 20, "reply.title")
  end

  defp button(_), do: fail("botão deve ser {type: reply, reply: {id, title}}")

  defp sections(list) when is_list(list) and length(list) in 1..10 do
    if Enum.all?(list, &(is_map(&1) and is_list(&1["rows"] || []))),
      do: valid_sections(list),
      else: fail("action.sections: cada seção precisa de rows (lista)")
  end

  defp sections(_), do: fail("action.sections deve ter de 1 a 10 seções")

  defp valid_sections(list) do
    rows = Enum.flat_map(list, &(&1["rows"] || []))

    cond do
      length(rows) not in 1..10 ->
        fail("list: total de linhas deve ser de 1 a 10")

      length(list) > 1 and Enum.any?(list, &(not is_binary(&1["title"]))) ->
        fail("list: seções precisam de title quando há mais de uma")

      true ->
        with :ok <- each(list, &section_title/1),
             :ok <- each(rows, &row/1),
             do: unique_rows(rows)
    end
  end

  defp section_title(%{"title" => title}) when is_binary(title),
    do: max_len(title, 24, "section.title")

  defp section_title(_), do: :ok

  defp row(row) do
    with {:ok, id} <- string(row, "id"),
         :ok <- max_len(id, 200, "row.id"),
         {:ok, title} <- string(row, "title"),
         :ok <- max_len(title, 24, "row.title") do
      case row["description"] do
        nil -> :ok
        description when is_binary(description) -> max_len(description, 72, "row.description")
        _ -> fail("row.description deve ser texto")
      end
    end
  end

  defp unique_rows(rows) do
    ids = Enum.map(rows, & &1["id"])
    if length(Enum.uniq(ids)) == length(ids), do: :ok, else: fail("list: ids de linha duplicados")
  end

  defp order_parameters(params) when is_map(params) do
    with {:ok, reference} <- string(params, "reference_id"),
         :ok <- reference_id(reference),
         :ok <- inclusion(params["type"], ~w(digital-goods physical-goods), "type"),
         :ok <- equal(params["payment_type"], "br", "payment_type"),
         :ok <- equal(params["currency"], "BRL", "currency"),
         {:ok, total} <- money(params["total_amount"], "total_amount"),
         :ok <- order(params["order"], total),
         do: payment_settings(params["payment_settings"])
  end

  defp order_parameters(_), do: fail("action.parameters é obrigatório")

  defp reference_id(reference) do
    if Regex.match?(~r/^[A-Za-z0-9_.\-]{1,60}$/, reference),
      do: :ok,
      else: fail("reference_id aceita apenas letras, números, _ - . e até 60 caracteres")
  end

  # `order` is optional in Meta's API; when present it must add up.
  defp order(nil, _total), do: :ok

  defp order(order, total) when is_map(order) do
    with :ok <- equal(order["status"], "pending", "order.status"),
         {:ok, items_sum} <- items(order["items"]),
         {:ok, subtotal} <- money(order["subtotal"], "order.subtotal"),
         {:ok, tax} <- optional_money(order["tax"], "order.tax"),
         {:ok, shipping} <- optional_money(order["shipping"], "order.shipping"),
         {:ok, discount} <- optional_money(order["discount"], "order.discount"),
         :ok <-
           check(
             items_sum == subtotal,
             "order.subtotal (#{subtotal}) difere da soma dos itens (#{items_sum})"
           ) do
      expected = subtotal + tax + shipping - discount

      check(
        total == expected,
        "total_amount (#{total}) difere de subtotal + tax + shipping - discount (#{expected})"
      )
    end
  end

  defp order(_order, _total), do: fail("order deve ser um objeto")

  defp items(list) when is_list(list) and list != [] do
    Enum.reduce_while(list, {:ok, 0}, fn item, {:ok, acc} ->
      with {:ok, _} <- string(item, "retailer_id"),
           {:ok, name} <- string(item, "name"),
           :ok <- max_len(name, 60, "item.name"),
           {:ok, amount} <- money(item["amount"], "item.amount"),
           {:ok, sale} <- optional_money(item["sale_amount"], "item.sale_amount"),
           :ok <- quantity(item["quantity"]) do
        unit = if item["sale_amount"], do: sale, else: amount
        {:cont, {:ok, acc + unit * item["quantity"]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp items(_), do: fail("order.items deve ser uma lista não vazia")

  defp quantity(q) when is_integer(q) and q > 0, do: :ok
  defp quantity(_), do: fail("item.quantity deve ser inteiro positivo")

  defp money(%{"value" => value, "offset" => 100}, _field) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp money(_, field), do: fail("#{field} deve ser {value: inteiro em centavos, offset: 100}")

  defp optional_money(nil, _field), do: {:ok, 0}
  defp optional_money(value, field), do: money(value, field)

  defp payment_settings(list) when is_list(list) and list != [],
    do: each(list, &payment_setting/1)

  defp payment_settings(_), do: fail("payment_settings deve ser uma lista não vazia")

  defp payment_setting(%{"type" => "pix_dynamic_code", "pix_dynamic_code" => pix})
       when is_map(pix) do
    with {:ok, _} <- string(pix, "code"),
         {:ok, _} <- string(pix, "merchant_name"),
         {:ok, _} <- string(pix, "key"),
         do: inclusion(pix["key_type"], @key_types, "pix_dynamic_code.key_type")
  end

  defp payment_setting(%{"type" => "payment_link", "payment_link" => link}) when is_map(link) do
    with {:ok, uri} <- string(link, "uri"), do: http_url(uri, "payment_link.uri")
  end

  defp payment_setting(%{"type" => type}) when type in ~w(pix_dynamic_code payment_link),
    do: fail("payment_settings: objeto #{type} ausente")

  defp payment_setting(setting),
    do: {:error, Error.unsupported("payment_settings.type=#{inspect(setting["type"])}")}

  defp equal(value, value, _field), do: :ok

  defp equal(value, expected, field),
    do: fail("#{field} deve ser #{inspect(expected)} (recebido #{inspect(value)})")

  defp inclusion(value, allowed, field) do
    if value in allowed,
      do: :ok,
      else:
        fail("#{field} deve ser um de #{Enum.join(allowed, ", ")} (recebido #{inspect(value)})")
  end

  defp check(true, _message), do: :ok
  defp check(false, message), do: fail(message)
end
