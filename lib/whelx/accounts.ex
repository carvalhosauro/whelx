defmodule Whelx.Accounts do
  @moduledoc "Configuration that survives resets: app, WABAs, phone numbers, tokens, settings."

  import Ecto.Query
  require Logger
  alias Whelx.{Attrs, Events, Ids, Repo}
  alias Whelx.Accounts.{AccessToken, App, PhoneNumber, Settings, Waba}

  # App

  def get_app, do: Repo.one(from a in App, limit: 1)

  def get_app! do
    get_app() ||
      raise "whelx app not configured; run Whelx.Accounts.bootstrap!/0 or POST /_whelx/seed"
  end

  def upsert_app(attrs) do
    attrs = Attrs.stringify(attrs)

    app = get_app()

    case attrs["id"] do
      new_id when is_binary(new_id) and new_id != "" and not is_nil(app) and new_id != app.id ->
        change_app_id(app, attrs)

      _ ->
        (app || %App{}) |> App.changeset(attrs) |> Repo.insert_or_update() |> notify()
    end
  end

  # The app id is a primary key referenced by wabas: insert the new row,
  # move the wabas, then drop the old row.
  defp change_app_id(%App{} = app, attrs) do
    base = Map.take(Map.from_struct(app), [:name, :app_secret, :verify_token, :webhook_url])

    Repo.transaction(fn ->
      with {:ok, new_app} <-
             %App{} |> App.changeset(Map.merge(Attrs.stringify(base), attrs)) |> Repo.insert() do
        Repo.update_all(from(w in Waba, where: w.app_id == ^app.id), set: [app_id: new_app.id])
        Repo.delete!(app)
        new_app
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> notify()
  end

  def regenerate_app_secret, do: upsert_app(%{"app_secret" => Ids.app_secret()})

  # WABAs

  def list_wabas, do: Repo.all(from w in Waba, order_by: [asc: w.inserted_at])

  def get_waba(id), do: Repo.get(Waba, to_string(id))

  def upsert_waba(attrs) do
    attrs = attrs |> Attrs.stringify() |> Map.put_new_lazy("app_id", fn -> get_app!().id end)

    load(Waba, attrs["id"])
    |> Waba.changeset(attrs)
    |> Repo.insert_or_update()
    |> notify()
  end

  def set_subscribed(waba_id, value) when is_boolean(value) do
    case get_waba(waba_id) do
      nil -> {:error, :not_found}
      waba -> waba |> Ecto.Changeset.change(subscribed: value) |> Repo.update() |> notify()
    end
  end

  def delete_waba(%Waba{} = waba), do: waba |> Repo.delete() |> notify()

  # Phone numbers

  def list_phone_numbers(waba_id),
    do:
      Repo.all(
        from p in PhoneNumber, where: p.waba_id == ^waba_id, order_by: [asc: p.inserted_at]
      )

  def list_all_phone_numbers, do: Repo.all(from p in PhoneNumber, order_by: [asc: p.inserted_at])

  def get_phone_number(id), do: Repo.get(PhoneNumber, to_string(id))

  def get_phone_number!(id), do: Repo.get!(PhoneNumber, to_string(id))

  def upsert_phone_number(attrs) do
    attrs = Attrs.stringify(attrs)

    load(PhoneNumber, attrs["id"])
    |> PhoneNumber.changeset(attrs)
    |> Repo.insert_or_update()
    |> notify()
  end

  def delete_phone_number(%PhoneNumber{} = phone), do: phone |> Repo.delete() |> notify()

  # Tokens

  def list_tokens, do: Repo.all(from t in AccessToken, order_by: [asc: t.inserted_at])

  def create_token(waba_ids, opts \\ []) do
    %AccessToken{}
    |> AccessToken.changeset(%{
      "token" => opts[:token],
      "waba_ids" => waba_ids,
      "expires_at" => opts[:expires_at]
    })
    |> Repo.insert()
    |> notify()
  end

  def upsert_token(attrs) do
    attrs = Attrs.stringify(attrs)

    load_token(attrs["token"])
    |> AccessToken.changeset(attrs)
    |> Repo.insert_or_update()
    |> notify()
  end

  def delete_token(%AccessToken{} = token), do: token |> Repo.delete() |> notify()

  @spec verify_token(term()) :: {:ok, AccessToken.t()} | :error
  def verify_token(token) when is_binary(token) and token != "" do
    case Repo.get(AccessToken, token) do
      nil -> :error
      %AccessToken{expires_at: nil} = t -> {:ok, t}
      t -> if DateTime.after?(t.expires_at, DateTime.utc_now()), do: {:ok, t}, else: :error
    end
  end

  def verify_token(_), do: :error

  @spec token_can_access?(AccessToken.t(), String.t()) :: boolean()
  def token_can_access?(%AccessToken{waba_ids: ids}, waba_id), do: to_string(waba_id) in ids

  # Settings

  def get_settings do
    Whelx.Cache.fetch(:settings, fn ->
      Repo.one(from s in Settings, order_by: [asc: s.id], limit: 1) || Repo.insert!(%Settings{})
    end)
  end

  def update_settings(attrs) do
    result = get_settings() |> Settings.changeset(Attrs.stringify(attrs)) |> Repo.update()
    Whelx.Cache.invalidate(:settings)
    notify(result)
  end

  # Bootstrap

  @doc "Creates a usable default configuration on first boot. Idempotent."
  @spec bootstrap!() :: :ok
  def bootstrap! do
    if is_nil(get_app()) do
      {:ok, _app} = upsert_app(%{})
      {:ok, waba} = upsert_waba(%{name: "Demo Store"})

      {:ok, _phone} =
        upsert_phone_number(%{
          waba_id: waba.id,
          display_phone_number: "+55 11 4000-0001",
          verified_name: "Demo Store"
        })

      {:ok, _token} = create_token([waba.id])
    end

    _ = get_settings()
    :ok
  end

  defp load(schema, nil), do: struct(schema)
  defp load(schema, id), do: Repo.get(schema, to_string(id)) || struct(schema)

  defp load_token(nil), do: %AccessToken{}
  defp load_token(token), do: Repo.get(AccessToken, token) || %AccessToken{}

  defp notify({:ok, _} = result) do
    Events.broadcast("config", :config_changed)
    result
  end

  defp notify(other), do: other
end
