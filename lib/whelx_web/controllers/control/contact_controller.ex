defmodule WhelxWeb.Control.ContactController do
  use WhelxWeb, :controller
  alias Whelx.{Contacts, Control, Messaging}
  alias Whelx.Control.JSON

  action_fallback WhelxWeb.Control.FallbackController

  def index(conn, _params), do: json(conn, Enum.map(Contacts.list_contacts(), &JSON.contact/1))

  def create(conn, params) do
    with {:ok, contact} <- Contacts.create_contact(params) do
      conn |> put_status(201) |> json(JSON.contact(contact))
    end
  end

  def show(conn, %{"wa_id" => wa_id}) do
    with {:ok, contact} <- fetch(wa_id), do: json(conn, JSON.contact(contact))
  end

  def update(conn, %{"wa_id" => wa_id} = params) do
    attrs = Map.drop(params, ["wa_id", "online"])

    with {:ok, contact} <- fetch(wa_id),
         {:ok, contact} <- Contacts.update_contact(contact, attrs),
         {:ok, contact} <- presence(contact, params["online"]) do
      json(conn, JSON.contact(contact))
    end
  end

  def delete(conn, %{"wa_id" => wa_id}) do
    with {:ok, contact} <- fetch(wa_id),
         {:ok, _} <- Contacts.delete_contact(contact) do
      send_resp(conn, 204, "")
    end
  end

  def bulk(conn, params) do
    count =
      params["count"]
      |> to_string()
      |> Integer.parse()
      |> then(fn
        {n, _} -> n
        :error -> 0
      end)

    with {:ok, count} <- Contacts.bulk_create(count) do
      conn |> put_status(201) |> json(%{"count" => count})
    end
  end

  def send_message(conn, %{"wa_id" => wa_id} = params) do
    with {:ok, message} <- Control.send_as_contact(wa_id, Map.delete(params, "wa_id")) do
      conn |> put_status(201) |> json(message_json(message))
    end
  end

  def reply_interactive(conn, %{"wa_id" => wa_id, "wamid" => wamid, "id" => id}) do
    with {:ok, message} <- Control.reply_interactive(wa_id, wamid, id) do
      conn |> put_status(201) |> json(message_json(message))
    end
  end

  def reply_interactive(_conn, _params), do: {:error, "wamid e id são obrigatórios"}

  defp message_json(message),
    do: message.wamid |> Messaging.get_message_by_wamid() |> JSON.message()

  defp fetch(wa_id) do
    case Contacts.get_contact(wa_id) do
      nil -> {:error, :not_found}
      contact -> {:ok, contact}
    end
  end

  defp presence(contact, nil), do: {:ok, contact}

  defp presence(contact, online) when is_boolean(online),
    do: Messaging.set_contact_online(contact, online)

  defp presence(contact, online),
    do: Messaging.set_contact_online(contact, online in ["true", "1"])
end
