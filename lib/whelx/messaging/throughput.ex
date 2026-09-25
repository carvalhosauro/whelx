defmodule Whelx.Messaging.Throughput do
  @moduledoc "Per-phone messages-per-second limiter (fixed 1 s windows in ETS)."
  use GenServer

  @table :whelx_throughput

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @spec check(String.t(), pos_integer(), integer()) :: :ok | {:error, :rate_limited}
  def check(phone_id, limit, second \\ System.os_time(:second)) do
    key = {phone_id, second}

    if :ets.update_counter(@table, key, {2, 1}, {key, 0}) > limit,
      do: {:error, :rate_limited},
      else: :ok
  end

  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_prune()
    {:ok, nil}
  end

  @impl true
  def handle_info(:prune, state) do
    cutoff = System.os_time(:second) - 5
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", cutoff}], [true]}])
    schedule_prune()
    {:noreply, state}
  end

  defp schedule_prune, do: Process.send_after(self(), :prune, 5_000)
end
