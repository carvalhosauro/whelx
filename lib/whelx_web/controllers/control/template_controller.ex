defmodule WhelxWeb.Control.TemplateController do
  use WhelxWeb, :controller
  alias Whelx.Templates
  alias Whelx.Control.JSON

  action_fallback WhelxWeb.Control.FallbackController

  def index(conn, params),
    do: json(conn, Enum.map(Templates.list_all(params["waba_id"]), &JSON.template/1))

  def approve(conn, %{"id" => id}) do
    with {:ok, template} <- fetch(id),
         {:ok, template} <- Templates.approve(template) do
      json(conn, JSON.template(template))
    end
  end

  def reject(conn, %{"id" => id} = params) do
    with {:ok, template} <- fetch(id),
         {:ok, template} <- Templates.reject(template, params["reason"] || "INVALID_FORMAT") do
      json(conn, JSON.template(template))
    end
  end

  defp fetch(id) do
    case Templates.get_template(id) do
      nil -> {:error, :not_found}
      template -> {:ok, template}
    end
  end
end
