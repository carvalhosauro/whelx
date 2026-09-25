defmodule Whelx.Cache do
  @moduledoc """
  Tiny read-through cache (persistent_term) for single-row configuration read
  on every Graph request (settings, chaos profile). Writers must `invalidate/1`.
  """

  @keys [:settings, :chaos_profile]

  @spec fetch(atom(), (-> term())) :: term()
  def fetch(key, loader) when key in @keys do
    case :persistent_term.get({__MODULE__, key}, :miss) do
      :miss ->
        value = loader.()
        :persistent_term.put({__MODULE__, key}, value)
        value

      value ->
        value
    end
  end

  @spec invalidate(atom()) :: :ok
  def invalidate(key) when key in @keys do
    :persistent_term.erase({__MODULE__, key})
    :ok
  end

  @spec clear() :: :ok
  def clear do
    Enum.each(@keys, &invalidate/1)
  end
end
