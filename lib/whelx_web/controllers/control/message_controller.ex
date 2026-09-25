defmodule WhelxWeb.Control.MessageController do
  use WhelxWeb, :controller
  alias Whelx.{Messaging, Repo}
  alias Whelx.Control.JSON
  alias Whelx.Messaging.Conversation

  action_fallback WhelxWeb.Control.FallbackController

  def index(conn, params),
    do: json(conn, Enum.map(Messaging.list_messages(params), &JSON.message/1))

  def show_conversation(conn, %{"id" => id}) do
    with {:ok, conversation} <- fetch(id), do: json(conn, JSON.conversation(conversation))
  end

  def open(conn, %{"id" => id}) do
    with {:ok, conversation} <- fetch(id) do
      :ok = Messaging.open_conversation(conversation.id)
      {:ok, conversation} = fetch(id)
      json(conn, JSON.conversation(conversation))
    end
  end

  def expire_window(conn, %{"id" => id}) do
    with {:ok, conversation} <- fetch(id),
         {:ok, _} <- Messaging.expire_window(conversation) do
      {:ok, conversation} = fetch(id)
      json(conn, JSON.conversation(conversation))
    end
  end

  defp fetch(id) do
    case Integer.parse(to_string(id)) do
      {int, ""} ->
        case Repo.get(Conversation, int) do
          nil -> {:error, :not_found}
          _ -> {:ok, Messaging.get_conversation!(int)}
        end

      _ ->
        {:error, :not_found}
    end
  end
end
