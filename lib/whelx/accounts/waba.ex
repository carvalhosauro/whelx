defmodule Whelx.Accounts.Waba do
  use Ecto.Schema
  import Ecto.Changeset
  import Whelx.ChangesetHelpers
  alias Whelx.Ids

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "wabas" do
    field :app_id, :string
    field :name, :string
    field :subscribed, :boolean, default: false
    field :override_callback_uri, :string
    field :override_verify_token, :string
    timestamps()
  end

  def changeset(waba, attrs) do
    waba
    |> cast(attrs, [
      :id,
      :app_id,
      :name,
      :subscribed,
      :override_callback_uri,
      :override_verify_token
    ])
    |> put_default(:id, &Ids.numeric_id/0)
    |> validate_required([:id, :app_id, :name])
    |> validate_http_url(:override_callback_uri)
  end
end
