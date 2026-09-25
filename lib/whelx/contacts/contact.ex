defmodule Whelx.Contacts.Contact do
  use Ecto.Schema
  import Ecto.Changeset
  import Whelx.ChangesetHelpers
  alias Whelx.{Attrs, Ids}
  alias Whelx.Contacts.Names

  @primary_key {:wa_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  @behaviors ~w(normal invalid_number blocked)
  @read_policies ~w(on_open auto never)

  schema "contacts" do
    field :profile_name, :string
    field :behavior, :string, default: "normal"
    field :online, :boolean, default: true
    field :read_policy, :string, default: "on_open"
    field :read_after_ms, :integer, default: 2000
    timestamps()
  end

  def behaviors, do: @behaviors
  def read_policies, do: @read_policies

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:wa_id, :profile_name, :behavior, :online, :read_policy, :read_after_ms])
    |> update_change(:wa_id, &Attrs.digits/1)
    |> put_default(:wa_id, &Ids.contact_wa_id/0)
    |> put_default(:profile_name, &Names.random/0)
    |> validate_required([:wa_id, :profile_name])
    |> validate_format(:wa_id, ~r/^\d{8,15}$/, message: "must have 8 to 15 digits")
    |> validate_inclusion(:behavior, @behaviors)
    |> validate_inclusion(:read_policy, @read_policies)
    |> validate_number(:read_after_ms, greater_than_or_equal_to: 0)
    |> unique_constraint(:wa_id, name: "contacts_pkey")
    |> unique_constraint(:wa_id)
  end
end
