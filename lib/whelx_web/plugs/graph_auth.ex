defmodule WhelxWeb.Plugs.GraphAuth do
  @moduledoc "Authenticates Graph requests with Bearer/OAuth header or ?access_token=."
  @behaviour Plug
  import Plug.Conn
  alias Whelx.Accounts
  alias Whelx.Graph.Error

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with token when is_binary(token) <- extract(conn),
         {:ok, access_token} <- Accounts.verify_token(token) do
      assign(conn, :access_token, access_token)
    else
      _ -> conn |> WhelxWeb.Graph.Render.error(Error.new(190)) |> halt()
    end
  end

  @spec extract(Plug.Conn.t()) :: String.t() | nil
  def extract(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> String.trim(token)
      ["OAuth " <> token | _] -> String.trim(token)
      _ -> conn.params["access_token"]
    end
  end
end
