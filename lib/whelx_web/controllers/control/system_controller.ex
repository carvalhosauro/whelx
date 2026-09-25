defmodule WhelxWeb.Control.SystemController do
  use WhelxWeb, :controller
  alias Whelx.{Accounts, Chaos, Control}
  alias Whelx.Control.JSON

  action_fallback WhelxWeb.Control.FallbackController

  def seed(conn, params) do
    with {:ok, snapshot} <- Control.seed(params), do: json(conn, snapshot)
  end

  def reset(conn, params) do
    keep =
      case params["keep"] do
        list when is_list(list) -> Enum.map(list, &to_string/1)
        csv when is_binary(csv) -> String.split(csv, ",", trim: true)
        _ -> []
      end

    :ok = Control.reset(keep)
    json(conn, %{"ok" => true})
  end

  def config(conn, _params), do: json(conn, Control.snapshot())

  def update_config(conn, params) do
    with {:ok, _} <- maybe(params["app"], &Accounts.upsert_app/1),
         {:ok, _} <- maybe(params["settings"], &Accounts.update_settings/1) do
      json(conn, Control.snapshot())
    end
  end

  def create_token(conn, params) do
    waba_ids = params["waba_ids"] || Enum.map(Accounts.list_wabas(), & &1.id)

    with {:ok, token} <- Accounts.create_token(waba_ids) do
      conn |> put_status(201) |> json(JSON.token(token))
    end
  end

  def chaos(conn, _params), do: json(conn, JSON.chaos(Chaos.get_profile()))

  def update_chaos(conn, %{"preset" => preset} = params) when map_size(params) == 1 do
    case Chaos.apply_preset(preset) do
      {:ok, profile} ->
        json(conn, JSON.chaos(profile))

      {:error, :unknown_preset} ->
        {:error, "preset desconhecido: #{preset} (use #{Enum.join(Chaos.presets(), ", ")})"}
    end
  end

  def update_chaos(conn, params) do
    with {:ok, profile} <- Chaos.update_profile(params), do: json(conn, JSON.chaos(profile))
  end

  defp maybe(nil, _fun), do: {:ok, nil}
  defp maybe(attrs, fun), do: fun.(attrs)
end
