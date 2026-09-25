defmodule Whelx.ThroughputTest do
  use ExUnit.Case
  alias Whelx.Messaging.Throughput

  setup do
    Throughput.reset()
    :ok
  end

  test "allows exactly `limit` calls per second under concurrency" do
    results =
      1..200
      |> Task.async_stream(fn _ -> Throughput.check("phone-x", 80, 1_000) end,
        max_concurrency: 50
      )
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(results, &(&1 == :ok)) == 80
    assert Enum.count(results, &(&1 == {:error, :rate_limited})) == 120
  end

  test "windows are per second and per phone" do
    assert :ok = Throughput.check("a", 1, 10)
    assert {:error, :rate_limited} = Throughput.check("a", 1, 10)
    assert :ok = Throughput.check("a", 1, 11)
    assert :ok = Throughput.check("b", 1, 10)
  end
end
