defmodule WhelxWeb.RawBodyReader do
  @moduledoc "Plug.Parsers body reader that keeps the raw body in `conn.assigns.raw_body`."

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, append(conn, body)}
      {:more, body, conn} -> {:more, body, append(conn, body)}
      other -> other
    end
  end

  defp append(conn, chunk),
    do: Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> chunk)
end
