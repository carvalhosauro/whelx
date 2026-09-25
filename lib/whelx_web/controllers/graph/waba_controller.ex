defmodule WhelxWeb.Graph.WabaController do
  use WhelxWeb, :controller
  alias Whelx.Accounts
  alias Whelx.Graph.{Error, Fields, JSON}
  alias WhelxWeb.Graph.{Authz, Render}

  action_fallback WhelxWeb.Graph.FallbackController

  @phone_fields ~w(id display_phone_number verified_name quality_rating)

  def phone_numbers(conn, %{"id" => id} = params) do
    with {:ok, waba} <- fetch_waba(id, "get"),
         :ok <- Authz.waba(conn.assigns.access_token, waba.id) do
      data =
        waba.id
        |> Accounts.list_phone_numbers()
        |> Enum.map(&Fields.select(JSON.phone_number(&1), params["fields"], @phone_fields))

      Render.ok(conn, %{"data" => data})
    end
  end

  def subscribe(conn, %{"id" => id}), do: set_subscribed(conn, id, true)
  def unsubscribe(conn, %{"id" => id}), do: set_subscribed(conn, id, false)

  defp set_subscribed(conn, id, value) do
    with {:ok, waba} <- fetch_waba(id, String.downcase(conn.method)),
         :ok <- Authz.waba(conn.assigns.access_token, waba.id),
         {:ok, _} <- Accounts.set_subscribed(waba.id, value) do
      Render.ok(conn, %{"success" => true})
    end
  end

  defp fetch_waba(id, method) do
    case Accounts.get_waba(id) do
      nil -> {:error, Error.unknown_object(method, id)}
      waba -> {:ok, waba}
    end
  end
end
