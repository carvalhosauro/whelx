defmodule Whelx.Chaos do
  @moduledoc """
  Chaos profile and deterministic decisions. The same seed and the same
  sequence of rolls per point produce the same outcomes.
  """

  import Ecto.Query
  alias Whelx.{Attrs, Events, Repo}
  alias Whelx.Chaos.{Counter, Profile}

  @presets %{
    "off" => %{
      latency_min_ms: 0,
      latency_max_ms: 0,
      sync_error_rate: 0.0,
      async_fail_rate: 0.0,
      reorder_rate: 0.0,
      duplicate_rate: 0.0,
      drop_rate: 0.0,
      batch_rate: 0.0,
      webhook_extra_delay_ms: 0
    },
    "flaky" => %{
      latency_min_ms: 20,
      latency_max_ms: 150,
      sync_error_rate: 0.02,
      async_fail_rate: 0.03,
      reorder_rate: 0.05,
      duplicate_rate: 0.03,
      drop_rate: 0.01,
      batch_rate: 0.1,
      webhook_extra_delay_ms: 500
    },
    "hostile" => %{
      latency_min_ms: 100,
      latency_max_ms: 1500,
      sync_error_rate: 0.15,
      async_fail_rate: 0.15,
      reorder_rate: 0.25,
      duplicate_rate: 0.15,
      drop_rate: 0.05,
      batch_rate: 0.3,
      webhook_extra_delay_ms: 3000
    }
  }

  @max_uint64 18_446_744_073_709_551_616

  @spec presets() :: [String.t()]
  def presets, do: ~w(off flaky hostile)

  @spec get_profile() :: Profile.t()
  def get_profile do
    Whelx.Cache.fetch(:chaos_profile, fn ->
      Repo.one(from p in Profile, order_by: [asc: p.id], limit: 1) || Repo.insert!(%Profile{})
    end)
  end

  def update_profile(attrs) do
    result = get_profile() |> Profile.changeset(Attrs.stringify(attrs)) |> Repo.update()
    Whelx.Cache.invalidate(:chaos_profile)

    with {:ok, profile} <- result do
      reset_counters()
      Events.broadcast("config", :chaos_changed)
      {:ok, profile}
    end
  end

  def apply_preset(name) when is_map_key(@presets, name),
    do: update_profile(Map.put(@presets[name], :preset, name))

  def apply_preset(_name), do: {:error, :unknown_preset}

  @spec active?(Profile.t()) :: boolean()
  def active?(%Profile{} = p) do
    p.latency_max_ms > 0 or p.webhook_extra_delay_ms > 0 or
      Enum.any?(Profile.rates(), &(Map.fetch!(p, &1) > 0))
  end

  @spec roll(Profile.t(), atom()) :: float()
  def roll(%Profile{seed: seed}, point) do
    n = Counter.next(point)

    <<int::unsigned-64, _::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary({seed, point, n}))

    int / @max_uint64
  end

  @spec hit?(Profile.t(), atom(), number()) :: boolean()
  def hit?(_profile, _point, rate) when rate <= 0, do: false
  def hit?(profile, point, rate), do: roll(profile, point) < rate

  @spec pick(Profile.t(), atom(), list()) :: term()
  def pick(_profile, _point, []), do: nil
  def pick(profile, point, list), do: Enum.at(list, trunc(roll(profile, point) * length(list)))

  @spec latency_ms(Profile.t()) :: non_neg_integer()
  def latency_ms(%Profile{latency_max_ms: 0}), do: 0

  def latency_ms(%Profile{latency_min_ms: min, latency_max_ms: max} = p),
    do: min + trunc(roll(p, :latency) * (max - min + 1))

  @spec reset_counters() :: :ok
  def reset_counters, do: Counter.reset()
end
