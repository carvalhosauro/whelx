defmodule Whelx.Messaging.Message do
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec]

  schema "messages" do
    field :wamid, :string
    belongs_to :conversation, Whelx.Messaging.Conversation
    field :direction, :string
    field :type, :string
    field :payload, :map, default: %{}
    field :status, :string
    field :errors, {:array, :map}, default: []
    field :context_wamid, :string
    field :planned_failure, :map
    field :chaos_tag, :string
    field :sent_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec
    field :read_at, :utc_datetime_usec
    field :failed_at, :utc_datetime_usec
    timestamps()
  end

  @doc "The type-specific object (e.g. `%{\"body\" => ...}` for text)."
  def content(%__MODULE__{payload: payload}), do: payload["content"] || %{}
end
