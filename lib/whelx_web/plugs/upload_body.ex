defmodule WhelxWeb.Plugs.UploadBody do
  @moduledoc """
  Captures the raw body of resumable upload chunks (`POST /vNN.N/upload:...`)
  before `Plug.Parsers` runs. Clients such as curl send binary chunks as
  `application/x-www-form-urlencoded`, which the urlencoded parser rejects.
  """
  @behaviour Plug
  import Plug.Conn

  @max 100_000_000

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST", path_info: [version, "upload:" <> _ | _]} = conn, _opts) do
    if Regex.match?(~r/^v\d+\.\d+$/, version) do
      {body, conn} = read_all(conn, [])

      conn
      |> assign(:raw_body, body)
      |> put_req_header("content-type", "application/octet-stream")
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp read_all(conn, acc) do
    case read_body(conn, length: @max) do
      {:ok, chunk, conn} -> {IO.iodata_to_binary(Enum.reverse([chunk | acc])), conn}
      {:more, chunk, conn} -> read_all(conn, [chunk | acc])
      {:error, _} -> {IO.iodata_to_binary(Enum.reverse(acc)), conn}
    end
  end
end
