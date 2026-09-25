defmodule Whelx.Graph.Fields do
  @moduledoc "Applies Graph `?fields=a,b` selection. `id` is always included."

  @spec select(map(), String.t() | nil, [String.t()]) :: map()
  def select(map, fields, default) do
    wanted =
      case fields do
        list when is_binary(list) and list != "" ->
          list |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

        _ ->
          default
      end

    Map.take(map, Enum.uniq(["id" | wanted]))
  end
end
