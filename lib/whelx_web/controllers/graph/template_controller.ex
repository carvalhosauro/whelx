defmodule WhelxWeb.Graph.TemplateController do
  use WhelxWeb, :controller
  alias Whelx.{Accounts, Templates}
  alias Whelx.Graph.Error
  alias WhelxWeb.Graph.{Authz, Render}

  action_fallback WhelxWeb.Graph.FallbackController

  def create(conn, %{"id" => id}) do
    with {:ok, waba} <- fetch_waba(conn, id),
         {:ok, template} <- Templates.create_template(waba.id, conn.body_params) do
      Render.ok(conn, %{
        "id" => template.id,
        "status" => template.status,
        "category" => template.category
      })
    end
  end

  def index(conn, %{"id" => id} = params) do
    with {:ok, waba} <- fetch_waba(conn, id) do
      page = Templates.list_templates(waba.id, params)

      paging =
        %{"cursors" => %{"before" => page.before, "after" => page.after || page.before}}
        |> then(fn paging ->
          if page.after, do: Map.put(paging, "next", next_url(conn, page.after)), else: paging
        end)

      Render.ok(conn, %{
        "data" => Enum.map(page.data, &Templates.to_graph(&1, params["fields"])),
        "paging" => paging
      })
    end
  end

  def delete(conn, %{"id" => id} = params) do
    with {:ok, waba} <- fetch_waba(conn, id),
         {:ok, name} <- required_name(params),
         {:ok, _count} <- Templates.delete_by_name(waba.id, name) do
      Render.ok(conn, %{"success" => true})
    end
  end

  defp fetch_waba(conn, id) do
    case Accounts.get_waba(id) do
      nil ->
        {:error, Error.unknown_object(String.downcase(conn.method), id)}

      waba ->
        with :ok <- Authz.waba(conn.assigns.access_token, waba.id), do: {:ok, waba}
    end
  end

  defp required_name(%{"name" => name}) when is_binary(name) and name != "", do: {:ok, name}
  defp required_name(_), do: {:error, Error.invalid_parameter("name é obrigatório")}

  defp next_url(conn, after_cursor) do
    query = conn.query_params |> Map.put("after", after_cursor) |> URI.encode_query()
    Whelx.public_url() <> conn.request_path <> "?" <> query
  end
end
