defmodule WhelxWeb.Graph.MessageController do
  use WhelxWeb, :controller
  alias Whelx.{Accounts, Messaging}
  alias Whelx.Graph.{Error, Validation}
  alias WhelxWeb.Graph.{Authz, Render}

  action_fallback WhelxWeb.Graph.FallbackController

  def create(conn, %{"id" => id}) do
    with {:ok, phone} <- fetch_phone(id),
         :ok <- Authz.waba(conn.assigns.access_token, phone.waba_id),
         {:ok, request} <- Validation.validate_send(conn.body_params) do
      respond(conn, phone, request)
    end
  end

  defp respond(conn, phone, %{kind: :read} = request) do
    with {:ok, _} <- Messaging.mark_read_by_business(phone.id, request.message_id, request.typing) do
      Render.ok(conn, %{"success" => true})
    end
  end

  defp respond(conn, phone, %{kind: :message} = request) do
    with {:ok, message} <- Messaging.send_outbound(phone, request) do
      Render.ok(conn, %{
        "messaging_product" => "whatsapp",
        "contacts" => [%{"input" => request.to_input, "wa_id" => request.to}],
        "messages" => [message_ref(message, request.type)]
      })
    end
  end

  # Meta only reports message_status for template messages.
  defp message_ref(message, "template"),
    do: %{"id" => message.wamid, "message_status" => "accepted"}

  defp message_ref(message, _type), do: %{"id" => message.wamid}

  defp fetch_phone(id) do
    case Accounts.get_phone_number(id) do
      nil -> {:error, Error.unknown_object("post", id)}
      phone -> {:ok, phone}
    end
  end
end
