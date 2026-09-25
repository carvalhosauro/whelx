defmodule WhelxWeb.McpController do
  use WhelxWeb, :controller

  def handle(conn, %{"jsonrpc" => "2.0", "method" => method} = request) do
    case Whelx.Mcp.handle(method, request["params"] || %{}) do
      :notification ->
        send_resp(conn, 202, "")

      {:ok, result} ->
        json(conn, %{"jsonrpc" => "2.0", "id" => request["id"], "result" => result})

      {:error, code, message} ->
        json(conn, %{
          "jsonrpc" => "2.0",
          "id" => request["id"],
          "error" => %{"code" => code, "message" => message}
        })
    end
  end

  def handle(conn, _params) do
    json(conn, %{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{"code" => -32_600, "message" => "Invalid Request"}
    })
  end

  def stream(conn, _params), do: send_resp(conn, 405, "")
end
