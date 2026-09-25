defmodule WhelxWeb.Graph.Render do
  @moduledoc "JSON responses in Graph API format."
  alias Whelx.Graph.Error

  def ok(conn, body), do: conn |> Plug.Conn.put_status(200) |> Phoenix.Controller.json(body)

  def error(conn, %Error{} = error) do
    conn |> Plug.Conn.put_status(error.status) |> Phoenix.Controller.json(Error.to_body(error))
  end
end
