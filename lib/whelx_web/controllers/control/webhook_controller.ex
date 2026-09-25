defmodule WhelxWeb.Control.WebhookController do
  use WhelxWeb, :controller
  alias Whelx.{Logs, Webhooks}
  alias Whelx.Control.JSON

  action_fallback WhelxWeb.Control.FallbackController

  def index(conn, params) do
    deliveries =
      Webhooks.list_deliveries(
        message_wamid: params["message_wamid"],
        state: params["state"],
        limit: limit(params)
      )

    json(conn, Enum.map(deliveries, &JSON.delivery/1))
  end

  def redeliver(conn, %{"id" => id}) do
    with {:ok, delivery} <- Webhooks.redeliver(id) do
      conn |> put_status(201) |> json(JSON.delivery(delivery))
    end
  end

  def verify(conn, _params) do
    with {:ok, result} <- Webhooks.verify(), do: json(conn, result)
  end

  def requests(conn, params) do
    json(
      conn,
      Enum.map(Logs.list_requests(limit: limit(params), path: params["path"]), &JSON.request/1)
    )
  end

  defp limit(params) do
    case Integer.parse(to_string(params["limit"] || "100")) do
      {n, _} -> min(max(n, 1), 1000)
      :error -> 100
    end
  end
end
