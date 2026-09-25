defmodule Whelx.Accounts.PhoneNumber do
  use Ecto.Schema
  import Ecto.Changeset
  import Whelx.ChangesetHelpers
  alias Whelx.Ids

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "phone_numbers" do
    field :waba_id, :string
    field :display_phone_number, :string
    field :verified_name, :string
    field :quality_rating, :string, default: "GREEN"
    field :throughput_mps, :integer, default: 80
    timestamps()
  end

  def changeset(phone, attrs) do
    phone
    |> cast(attrs, [
      :id,
      :waba_id,
      :display_phone_number,
      :verified_name,
      :quality_rating,
      :throughput_mps
    ])
    |> put_default(:id, &Ids.numeric_id/0)
    |> validate_required([:id, :waba_id, :display_phone_number, :verified_name])
    |> validate_inclusion(:quality_rating, ~w(GREEN YELLOW RED UNKNOWN))
    |> validate_number(:throughput_mps, greater_than: 0)
  end
end
