defmodule Whelx.CacheTest do
  use ExUnit.Case
  alias Whelx.Cache

  setup do
    Cache.clear()
    on_exit(&Cache.clear/0)
  end

  test "reloads when the cached struct comes from an older module version" do
    stale = Map.delete(%Whelx.Accounts.Settings{}, :pair_rate_limit_enabled)
    :persistent_term.put({Cache, :settings}, {:stale_md5, stale})
    value = Cache.fetch(:settings, fn -> %Whelx.Accounts.Settings{} end)
    assert Map.has_key?(value, :pair_rate_limit_enabled)
  end

  test "serves the cached value while the module is unchanged" do
    first = Cache.fetch(:settings, fn -> %Whelx.Accounts.Settings{sent_delay_ms: 1} end)
    second = Cache.fetch(:settings, fn -> %Whelx.Accounts.Settings{sent_delay_ms: 2} end)
    assert first.sent_delay_ms == 1 and second.sent_delay_ms == 1
  end
end
