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

      {:media, media} ->
        Render.ok(conn, Whelx.Media.graph_json(media))

      {:upload_session, session} ->
        Render.ok(conn, %{"id" => session.id, "file_offset" => session.offset})

      _ ->
        {:error, Error.unknown_object("get", id)}
    end
  end

  def create(conn, %{"id" => "upload:" <> _ = id}) do
    {binary, conn} = raw_body(conn)
    offset = conn |> get_req_header("file_offset") |> List.first("0") |> String.to_integer()

    case Whelx.Media.append_upload(id, offset, binary) do
      {:ok, %{handle: handle}} when is_binary(handle) -> Render.ok(conn, %{"h" => handle})
      {:ok, session} -> Render.ok(conn, %{"id" => session.id, "file_offset" => session.offset})
      {:error, _} = error -> error
    end
  rescue
    ArgumentError -> {:error, Error.invalid_parameter("file_offset inválido")}
  end

  def create(_conn, %{"id" => id}), do: {:error, Error.unknown_object("post", id)}

  defp raw_body(conn) do
    case conn.assigns[:raw_body] do
      nil -> read_all(conn, "")
      body -> {body, conn}
    end
  end

  defp read_all(conn, acc) do
    case Plug.Conn.read_body(conn, length: 100_000_000) do
      {:ok, chunk, conn} -> {acc <> chunk, assign(conn, :raw_body, acc <> chunk)}
      {:more, chunk, conn} -> read_all(conn, acc <> chunk)
      {:error, _} -> {acc, conn}
    end
  end

  def unsupported(conn, %{"rest" => [id | _]}) do
    if Regex.match?(~r/^\d+$/, id) and ObjectResolver.resolve(id) == :not_found,
      do: {:error, Error.unknown_object(String.downcase(conn.method), id)},
      else: {:error, Error.unsupported("#{conn.method} #{conn.request_path}")}
  end

  def unsupported(conn, _params),
    do: {:error, Error.unsupported("#{conn.method} #{conn.request_path}")}
end
