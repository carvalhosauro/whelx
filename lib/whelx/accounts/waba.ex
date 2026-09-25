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
    timestamps()
  end

  def changeset(waba, attrs) do
    waba
    |> cast(attrs, [:id, :app_id, :name, :subscribed])
    |> put_default(:id, &Ids.numeric_id/0)
    |> validate_required([:id, :app_id, :name])
  end
end
