defmodule Whelx.Webhooks.Delivery do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]
  @states ~w(pending retrying delivered failed skipped dropped merged)

  schema "webhook_deliveries" do
    field :waba_id, :string
    field :kind, :string
    field :payload, :map
    field :body, :string
    field :signature, :string
    field :state, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :last_status, :integer
    field :last_response_body, :string
    field :last_error, :string
    field :latency_ms, :integer
    field :chaos_tag, :string
    field :message_wamid, :string
    field :batch, :boolean, default: false
    field :merged_into_id, :integer
    timestamps()
  end

  def states, do: @states

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :waba_id,
      :kind,
      :payload,
      :state,
      :last_error,
      :chaos_tag,
      :message_wamid,
      :batch
    ])
    |> validate_required([:kind, :payload, :state])
    |> validate_inclusion(:kind, ~w(messages statuses))
    |> validate_inclusion(:state, @states)
  end
end
