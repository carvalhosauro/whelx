defmodule Whelx.Attrs do
  @moduledoc "Helpers for attribute maps that may arrive with atom or string keys."

  @spec stringify(map() | keyword() | nil) :: map()
  def stringify(nil), do: %{}
  def stringify(attrs) when is_list(attrs), do: attrs |> Map.new() |> stringify()
  def stringify(attrs) when is_map(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

  @spec digits(term()) :: String.t()
  def digits(nil), do: ""
  def digits(value), do: String.replace(to_string(value), ~r/\D/, "")

  @spec unix(DateTime.t()) :: String.t()
  def unix(%DateTime{} = dt), do: dt |> DateTime.to_unix() |> Integer.to_string()
end
