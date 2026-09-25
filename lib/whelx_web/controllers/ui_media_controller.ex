defmodule WhelxWeb.UiMediaController do
  @moduledoc "Serves stored media to the local UI (no token needed)."
  use WhelxWeb, :controller
  alias Whelx.Media

  def show(conn, %{"id" => id}) do
    with %Media.MediaFile{} = media <- Media.get_media(id),
         {:ok, binary} <- Media.read_binary(media) do
      conn |> put_resp_content_type(media.mime_type, nil) |> send_resp(200, binary)
    else
      _ -> send_resp(conn, 404, "not found")
    end
  end
end
