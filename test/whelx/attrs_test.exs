defmodule Whelx.AttrsTest do
  use ExUnit.Case, async: true
  alias Whelx.Attrs

  test "stringify/1 converts atom keys and keyword lists" do
    assert Attrs.stringify(%{"b" => 2, a: 1}) == %{"a" => 1, "b" => 2}
    assert Attrs.stringify(a: 1) == %{"a" => 1}
    assert Attrs.stringify(nil) == %{}
  end

  test "digits/1 strips formatting" do
    assert Attrs.digits("+55 (11) 99999-0000") == "5511999990000"
    assert Attrs.digits(nil) == ""
  end

  test "unix/1 renders seconds as a string" do
    assert Attrs.unix(~U[2026-09-24 12:00:00Z]) == "1790251200"
  end
end
