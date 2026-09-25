defmodule WhelxWeb.Plugs.GraphVersion do
  @moduledoc "Rejects `/:version/...` paths whose version is not `vNN.N`."
  @behaviour Plug
  alias Whelx.Graph.Error

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_params: %{"version" => version}} = conn, _opts) do
    if Regex.match?(~r/^v\d+\.\d+$/, version) do
      conn
    else
      error = Error.new(2500, message: "Unknown path components: #{conn.request_path}")
      conn |> WhelxWeb.Graph.Render.error(error) |> Plug.Conn.halt()
    end
  end

  def call(conn, _opts), do: conn
end
