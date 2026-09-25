defmodule Whelx.Graph.ErrorTest do
  use ExUnit.Case, async: true
  alias Whelx.Graph.Error

  test "new/2 uses Meta defaults for status and message" do
    assert %Error{
             status: 404,
             message: "(#132001) Template name does not exist in the translation"
           } =
             Error.new(132_001)

    assert %Error{status: 401} = Error.new(190)
    assert %Error{status: 400} = Error.new(130_429)
    assert %Error{status: 503} = Error.new(2)
  end

  test "to_body/1 renders the Meta envelope and omits empty optionals" do
    body = Error.to_body(Error.new(100))

    assert %{"error" => %{"code" => 100, "type" => "OAuthException", "fbtrace_id" => trace}} =
             body

    assert is_binary(trace)
    refute Map.has_key?(body["error"], "error_subcode")

    body = Error.to_body(Error.invalid_parameter("invalid name", subcode: 2_388_024))
    assert body["error"]["error_subcode"] == 2_388_024
    assert body["error"]["error_user_msg"] == "invalid name"
  end

  test "unknown_object/2 mirrors Meta's missing object error" do
    error = Error.unknown_object("get", "123")
    assert error.code == 100
    assert error.subcode == 33
    assert error.message =~ "Object with ID '123' does not exist"
  end

  test "unsupported/1 flags whelx gaps loudly" do
    assert Error.unsupported("type=image").user_msg == "whelx: not supported (type=image)"
  end

  test "async/2 builds webhook status errors" do
    assert %{
             "code" => 131_047,
             "title" => "Re-engagement message",
             "error_data" => %{"details" => _}
           } =
             Error.async(131_047)

    assert Error.async(131_026, details: "Receiver blocked the business")["error_data"]["details"] ==
             "Receiver blocked the business"
  end
end
