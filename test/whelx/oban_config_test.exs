defmodule Whelx.ObanConfigTest do
  use ExUnit.Case, async: true

  test "Lifeline rescues orphaned jobs after longer than a webhook HTTP attempt can take" do
    plugins = Application.fetch_env!(:whelx, Oban)[:plugins]
    assert {Oban.Plugins.Lifeline, opts} = List.keyfind(plugins, Oban.Plugins.Lifeline, 0)
    assert opts[:rescue_after] > 3 * Whelx.Webhooks.Client.timeout_ms()
  end
end
