defmodule Whelx.Repo.Migrations.CreateWebhookDeliveries do
  use Ecto.Migration

  def change do
    create table(:webhook_deliveries) do
      add :waba_id, :string
      add :kind, :string, null: false
      add :payload, :map, null: false
      add :body, :text
      add :signature, :string
      add :state, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :last_status, :integer
      add :last_response_body, :text
      add :last_error, :text
      add :latency_ms, :integer
      add :chaos_tag, :string
      add :message_wamid, :string
      add :batch, :boolean, null: false, default: false
      add :merged_into_id, :integer
      timestamps(type: :utc_datetime_usec)
    end

    create index(:webhook_deliveries, [:message_wamid])
    create index(:webhook_deliveries, [:state])
  end
end
