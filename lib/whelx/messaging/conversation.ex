defmodule Whelx.Messaging.Conversation do
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec]

  schema "conversations" do
    field :phone_number_id, :string

    belongs_to :contact, Whelx.Contacts.Contact,
      foreign_key: :contact_wa_id,
      references: :wa_id,
      type: :string

    field :window_expires_at, :utc_datetime_usec
    field :typing_until, :utc_datetime_usec
    field :unread_count, :integer, default: 0
    field :last_message_at, :utc_datetime_usec
    has_many :messages, Whelx.Messaging.Message, preload_order: [asc: :id]
    timestamps()
  end
end
