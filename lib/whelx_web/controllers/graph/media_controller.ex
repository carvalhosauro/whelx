defmodule WhelxWeb.Graph.MediaController do
  use WhelxWeb, :controller
  alias Whelx.Media
  alias Whelx.Graph.Error

  action_fallback WhelxWeb.Graph.FallbackController

  def download(conn, %{"media_id" => id}) do
    with %Media.MediaFile{} = media <-
           Media.get_media(id) || {:error, Error.unknown_object("get", id)},
         {:ok, binary} <- Media.read_binary(media) do
      conn
      |> put_resp_content_type(media.mime_type, nil)
      |> send_resp(200, binary)
    else
      {:error, %Error{}} = error -> error
      {:error, _posix} -> {:error, Error.new(131_000, details: "media file missing on disk")}
    end
  end
end
