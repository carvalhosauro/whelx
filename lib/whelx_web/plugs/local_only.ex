defmodule WhelxWeb.Plugs.LocalOnly do
  @moduledoc """
  Guards the unauthenticated control API and MCP endpoint against requests
  driven by other websites: rejects a foreign `Origin` (also required by the
  MCP Streamable HTTP spec against DNS rebinding) and non-JSON request bodies,
  which a cross-site HTML form could otherwise send.
  """
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    cond do
      foreign_origin?(conn) -> reject(conn, 403, "origin não permitida")
      form_body?(conn) -> reject(conn, 415, "use content-type: application/json")
      true -> conn
    end
  end

  defp foreign_origin?(conn) do
    case get_req_header(conn, "origin") do
      [] -> false
      ["null" | _] -> true
      [origin | _] -> URI.parse(origin).host != conn.host
    end
  end

  defp form_body?(conn) do
    case get_req_header(conn, "content-type") do
      [type | _] ->
        String.starts_with?(type, [
          "application/x-www-form-urlencoded",
          "multipart/form-data",
          "text/plain"
        ])

      [] ->
        false
    end
  end

  defp reject(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{"error" => message}))
    |> halt()
  end
end
