defmodule Whelx.Chaos.Counter do
  @moduledoc "Owns the ETS table with per-point roll counters (determinism by sequence)."
  use GenServer

  @table :whelx_chaos_counters

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @spec next(atom()) :: pos_integer()
  def next(point), do: :ets.update_counter(@table, point, {2, 1}, {point, 0})

  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    {:ok, nil}
  end
end
