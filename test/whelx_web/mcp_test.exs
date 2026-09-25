defmodule WhelxWeb.McpTest do
  use WhelxWeb.ConnCase
  import Whelx.Fixtures

  setup do
    Whelx.Messaging.Throughput.reset()
    account_fixture()
  end

  defp rpc(method, params \\ %{}, id \\ 1),
    do:
      build_conn()
      |> post("/_whelx/mcp", %{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => method,
        "params" => params
      })

  test "initialize advertises tools" do
    assert %{
             "jsonrpc" => "2.0",
             "id" => 1,
             "result" => %{
               "protocolVersion" => "2025-06-18",
               "capabilities" => %{"tools" => %{}},
               "serverInfo" => %{"name" => "whelx"}
             }
           } =
             json_response(rpc("initialize", %{"protocolVersion" => "2025-06-18"}), 200)
  end

  test "notifications get 202 with no body" do
    conn =
      build_conn()
      |> post("/_whelx/mcp", %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    assert conn.status == 202
  end

  test "tools/list includes the core tools with input schemas" do
    %{"result" => %{"tools" => tools}} = json_response(rpc("tools/list"), 200)
    names = Enum.map(tools, & &1["name"])

    for name <-
          ~w(seed reset get_config send_as_contact reply_interactive wait_for list_messages approve_template set_chaos list_webhook_deliveries),
        do: assert(name in names)

    assert Enum.all?(
             tools,
             &match?(%{"inputSchema" => %{"type" => "object"}, "description" => _}, &1)
           )
  end

  test "tools/call send_as_contact and list_messages" do
    %{"result" => %{"content" => [%{"type" => "text", "text" => text}], "isError" => false}} =
      json_response(
        rpc("tools/call", %{
          "name" => "send_as_contact",
          "arguments" => %{"wa_id" => "5511977776666", "type" => "text", "text" => "oi"}
        }),
        200
      )

    assert %{"direction" => "inbound", "content" => %{"body" => "oi"}} = Jason.decode!(text)

    %{"result" => %{"content" => [%{"text" => list}]}} =
      json_response(
        rpc("tools/call", %{
          "name" => "list_messages",
          "arguments" => %{"contact" => "5511977776666"}
        }),
        200
      )

    assert [%{"wamid" => _}] = Jason.decode!(list)
  end

  test "tool errors come back as isError results" do
    %{"result" => %{"isError" => true, "content" => [%{"text" => msg}]}} =
      json_response(
        rpc("tools/call", %{
          "name" => "send_as_contact",
          "arguments" => %{"wa_id" => "5511977776666", "type" => "sticker"}
        }),
        200
      )

    assert msg =~ "sticker"
  end

  test "unknown method and unknown tool" do
    assert %{"error" => %{"code" => -32601}} = json_response(rpc("resources/list"), 200)

    assert %{"error" => %{"code" => -32602}} =
             json_response(rpc("tools/call", %{"name" => "nope", "arguments" => %{}}), 200)
  end

  test "GET is not supported" do
    assert build_conn() |> get("/_whelx/mcp") |> response(405)
  end
end
