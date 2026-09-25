defmodule Whelx.Cache do
  @moduledoc """
  Tiny read-through cache (persistent_term) for single-row configuration read
  on every Graph request (settings, chaos profile). Writers must `invalidate/1`.

  Entries are tagged with the schema module's MD5, so a hot code reload that
  changes the schema never serves a struct missing the new fields.
  """

  @keys [:settings, :chaos_profile]

  @spec fetch(atom(), (-> struct())) :: struct()
  def fetch(key, loader) when key in @keys do
    case :persistent_term.get({__MODULE__, key}, :miss) do
      {md5, %module{} = value} ->
        if md5 == module.module_info(:md5), do: value, else: load(key, loader)

      _ ->
        load(key, loader)
    end
  end

  defp load(key, loader) do
    %module{} = value = loader.()
    :persistent_term.put({__MODULE__, key}, {module.module_info(:md5), value})
    value
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
