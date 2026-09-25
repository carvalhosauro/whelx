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

  # POST without body removes the WABA override (Meta behaviour); with
  # override_callback_uri + verify_token the callback is verified first.
  def subscribe(conn, %{"id" => id}) do
    params = conn.body_params

    with {:ok, waba} <- fetch_waba(id, "post"),
         :ok <- Authz.waba(conn.assigns.access_token, waba.id),
         {:ok, override} <-
           verified_override(params["override_callback_uri"], params["verify_token"]),
         {:ok, _} <-
           Accounts.upsert_waba(%{
             "id" => waba.id,
             "subscribed" => true,
             "override_callback_uri" => override[:uri],
             "override_verify_token" => override[:token]
           }) do
      Render.ok(conn, %{"success" => true})
    end
  end

  def unsubscribe(conn, %{"id" => id}), do: set_subscribed(conn, id, false)

  def subscribed_apps(conn, %{"id" => id}) do
    with {:ok, waba} <- fetch_waba(id, "get"),
         :ok <- Authz.waba(conn.assigns.access_token, waba.id) do
      app = Accounts.get_app!()

      data =
        if waba.subscribed do
          entry = %{
            "whatsapp_business_api_data" => %{
              "id" => app.id,
              "link" => "https://www.facebook.com/games/?app_id=" <> app.id,
              "name" => app.name
            }
          }

          [
            if(waba.override_callback_uri,
              do: Map.put(entry, "override_callback_uri", waba.override_callback_uri),
              else: entry
            )
          ]
        else
          []
        end

      Render.ok(conn, %{"data" => data})
    end
  end

  @doc false
  def verified_override(uri, _token) when uri in [nil, ""], do: {:ok, %{uri: nil, token: nil}}

  def verified_override(uri, token) do
    case Whelx.Webhooks.verify_url(uri, token) do
      {:ok, %{ok: true}} ->
        {:ok, %{uri: uri, token: token}}

      other ->
        detail =
          case other do
            {:ok, %{status: status}} -> "HTTP #{status} ou hub.challenge não ecoado"
            {:error, reason} -> reason
          end

        {:error,
         Error.new(2200,
           user_msg: "Callback verification failed with the following errors: #{detail}"
         )}
    end
  end

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
