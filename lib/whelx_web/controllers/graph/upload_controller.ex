defmodule WhelxWeb.Graph.UploadController do
  use WhelxWeb, :controller
  alias Whelx.{Accounts, Media}
  alias Whelx.Graph.Error
  alias WhelxWeb.Graph.Render

  action_fallback WhelxWeb.Graph.FallbackController

  def create(conn, %{"id" => app_id} = params) do
    with :ok <- ensure_app(app_id),
         {:ok, session} <- Media.create_upload_session(app_id, params) do
      Render.ok(conn, %{"id" => session.id})
    end
  end

  defp ensure_app(app_id) do
    case Accounts.get_app() do
      %{id: ^app_id} -> :ok
      _ -> {:error, Error.unknown_object("post", app_id)}
    end
  end
end
