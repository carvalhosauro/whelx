defmodule Whelx.BootTest do
  use Whelx.DataCase

  test "oban runs with the SQLite engine" do
    assert Oban.config().engine == Oban.Engines.Lite
  end

  test "public_url and data_dir are configured" do
    assert Whelx.public_url() == "http://whelx.test"
    assert Whelx.data_dir() =~ "tmp/test_data"
  end
end
