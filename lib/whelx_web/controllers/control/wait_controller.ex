defmodule WhelxWeb.Control.WaitController do
  use WhelxWeb, :controller

  action_fallback WhelxWeb.Control.FallbackController

  def create(conn, params) do
    case Whelx.Control.Waiter.wait(params) do
      {:ok, found} ->
        json(conn, found)

      {:timeout, observed} ->
        conn |> put_status(408) |> json(%{"error" => "timeout", "observed" => observed})

      {:error, _} = error ->
        error
    end
  end
end
