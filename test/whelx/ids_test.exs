defmodule Whelx.IdsTest do
  use ExUnit.Case, async: true
  alias Whelx.Ids

  test "numeric ids are 15 digits and never start with zero" do
    for _ <- 1..50 do
      id = Ids.numeric_id()
      assert id =~ ~r/^[1-9]\d{14}$/
    end
  end

  test "tokens and wamids carry Meta prefixes" do
    assert String.starts_with?(Ids.access_token(), "EAA")
    assert String.starts_with?(Ids.wamid(), "wamid.")
    assert String.starts_with?(Ids.upload_session_id(), "upload:")
    assert Ids.media_handle() =~ ~r/^4:/
  end

  test "secrets and contact numbers have the expected shape" do
    assert Ids.app_secret() =~ ~r/^[0-9a-f]{32}$/
    assert Ids.contact_wa_id() =~ ~r/^55119\d{8}$/
    assert String.length(Ids.fbtrace_id()) == 11
    assert Ids.numeric_id() != Ids.numeric_id()
  end
end
