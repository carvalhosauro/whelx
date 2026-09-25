defmodule WhelxWeb.Graph.ObjectController do
  use WhelxWeb, :controller
  alias Whelx.Graph.{Error, Fields, JSON, ObjectResolver}
  alias WhelxWeb.Graph.{Authz, Render}

  action_fallback WhelxWeb.Graph.FallbackController

  @phone_fields ~w(id display_phone_number verified_name quality_rating)

  def show(conn, %{"id" => id} = params) do
    token = conn.assigns.access_token

    case ObjectResolver.resolve(id) do
      {:waba, waba} ->
        with :ok <- Authz.waba(token, waba.id),
             do: Render.ok(conn, Fields.select(JSON.waba(waba), params["fields"], ~w(id name)))

      {:phone_number, phone} ->
        with :ok <- Authz.waba(token, phone.waba_id),
             do:
               Render.ok(
                 conn,
                 Fields.select(JSON.phone_number(phone), params["fields"], @phone_fields)
               )

      {:app, app} ->
        Render.ok(conn, %{"id" => app.id, "name" => app.name})

      _ ->
        {:error, Error.unknown_object("get", id)}
    end
  end

  def create(_conn, %{"id" => id}), do: {:error, Error.unknown_object("post", id)}

  def unsupported(conn, %{"rest" => [id | _]}) do
    if Regex.match?(~r/^\d+$/, id) and ObjectResolver.resolve(id) == :not_found,
      do: {:error, Error.unknown_object(String.downcase(conn.method), id)},
      else: {:error, Error.unsupported("#{conn.method} #{conn.request_path}")}
  end

  def unsupported(conn, _params),
    do: {:error, Error.unsupported("#{conn.method} #{conn.request_path}")}
end
