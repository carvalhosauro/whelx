defmodule WhelxWeb.Graph.FallbackController do
  use WhelxWeb, :controller

  def call(conn, {:error, %Whelx.Graph.Error{} = error}),
    do: WhelxWeb.Graph.Render.error(conn, error)
end
