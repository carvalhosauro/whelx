defmodule Whelx.Messaging.PairLimit do
  @moduledoc """
  Meta's pair rate limit (business number → same WhatsApp user): a token
  bucket of `burst` messages refilled at 1 token per `interval_ms`
  (Meta: 45 burst, 1 every 6 s). Exceeding it is error 131056.
  """
  use GenServer

  @table :whelx_pair_limit

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @spec check(String.t(), String.t(), pos_integer(), pos_integer(), integer()) ::
          :ok | {:error, :pair_limited}
  def check(phone_id, wa_id, burst, interval_ms, now_ms \\ System.monotonic_time(:millisecond)) do
    GenServer.call(__MODULE__, {:check, {phone_id, wa_id}, burst, interval_ms, now_ms})
  end

  @spec reset() :: :ok
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :set, :protected])
    {:ok, nil}
  end

  @impl true
  def handle_call({:check, key, burst, interval_ms, now}, _from, state) do
    {tokens, last} =
      case :ets.lookup(@table, key) do
        [{^key, tokens, last}] -> {min(burst * 1.0, tokens + (now - last) / interval_ms), now}
        [] -> {burst * 1.0, now}
      end

    if tokens >= 1 do
      :ets.insert(@table, {key, tokens - 1, last})
      {:reply, :ok, state}
    else
      :ets.insert(@table, {key, tokens, last})
      {:reply, {:error, :pair_limited}, state}
    end
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end
end
