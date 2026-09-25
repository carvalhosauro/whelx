defmodule Whelx.Accounts.App do
  use Ecto.Schema
  import Ecto.Changeset
  import Whelx.ChangesetHelpers
  alias Whelx.Ids

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "apps" do
    field :name, :string, default: "whelx"
    field :app_secret, :string
    field :verify_token, :string
    field :webhook_url, :string
    timestamps()
  end

  def changeset(app, attrs) do
    app
    |> cast(attrs, [:id, :name, :app_secret, :verify_token, :webhook_url])
    |> put_default(:id, &Ids.numeric_id/0)
    |> put_default(:app_secret, &Ids.app_secret/0)
    |> put_default(:verify_token, &Ids.verify_token/0)
    |> validate_required([:id, :name, :app_secret, :verify_token])
    |> validate_http_url(:webhook_url)
  end
end
