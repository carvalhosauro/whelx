defmodule Whelx.Accounts.AccessToken do
  use Ecto.Schema
  import Ecto.Changeset
  import Whelx.ChangesetHelpers
  alias Whelx.Ids

  @primary_key {:token, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "access_tokens" do
    field :waba_ids, {:array, :string}, default: []
    field :expires_at, :utc_datetime_usec
    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:token, :waba_ids, :expires_at])
    |> put_default(:token, &Ids.access_token/0)
    |> validate_required([:token])
    |> validate_format(:token, ~r/^EAA/, message: "must start with EAA")
  end
end
