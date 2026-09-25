defmodule Whelx.ChaosTest do
  use Whelx.DataCase
  alias Whelx.Chaos

  setup do
    Chaos.reset_counters()
    :ok
  end

  test "the default profile is off and inactive" do
    profile = Chaos.get_profile()
    assert profile.preset == "off"
    refute Chaos.active?(profile)
  end

  test "rolls are deterministic for the same seed and sequence" do
    profile = Chaos.get_profile()
    first = for _ <- 1..20, do: Chaos.roll(profile, :sync_error)
    Chaos.reset_counters()
    second = for _ <- 1..20, do: Chaos.roll(profile, :sync_error)
    assert first == second
    assert Enum.all?(first, &(&1 >= 0 and &1 < 1))

    Chaos.reset_counters()
    {:ok, other} = Chaos.update_profile(%{seed: 7})
    third = for _ <- 1..20, do: Chaos.roll(other, :sync_error)
    refute first == third
  end

  test "hit?/3 never fires at rate 0 and always fires at rate 1" do
    profile = Chaos.get_profile()
    refute Enum.any?(1..50, fn _ -> Chaos.hit?(profile, :drop, 0.0) end)
    assert Enum.all?(1..50, fn _ -> Chaos.hit?(profile, :drop, 1.0) end)
  end

  test "pick/3 returns an element of the list" do
    profile = Chaos.get_profile()
    for _ <- 1..30, do: assert(Chaos.pick(profile, :code, [1, 2, 3]) in [1, 2, 3])
    assert Chaos.pick(profile, :code, []) == nil
  end

  test "latency_ms/1 stays within the configured range" do
    {:ok, profile} = Chaos.update_profile(%{latency_min_ms: 10, latency_max_ms: 20})
    for _ <- 1..50, do: assert(Chaos.latency_ms(profile) in 10..20)
  end

  test "apply_preset/1 loads known presets and rejects unknown ones" do
    assert {:ok, %{preset: "flaky", sync_error_rate: 0.02} = flaky} = Chaos.apply_preset("flaky")
    assert Chaos.active?(flaky)
    assert {:ok, %{preset: "off"} = off} = Chaos.apply_preset("off")
    refute Chaos.active?(off)
    assert {:error, :unknown_preset} = Chaos.apply_preset("apocalypse")
  end

  test "update_profile/1 validates rates and latency range" do
    assert {:error, cs} = Chaos.update_profile(%{drop_rate: 1.5})
    assert errors_on(cs).drop_rate != []
    assert {:error, cs} = Chaos.update_profile(%{latency_min_ms: 50, latency_max_ms: 10})
    assert errors_on(cs).latency_max_ms != []
  end
end
