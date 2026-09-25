defmodule Whelx.Repo.Migrations.CreateMessaging do
  use Ecto.Migration

  def change do
    create table(:contacts, primary_key: false) do
      add :wa_id, :string, primary_key: true
      add :profile_name, :string, null: false
      add :behavior, :string, null: false, default: "normal"
      add :online, :boolean, null: false, default: true
      add :read_policy, :string, null: false, default: "on_open"
      add :read_after_ms, :integer, null: false, default: 2000
      timestamps(type: :utc_datetime_usec)
    end

    create table(:conversations) do
      add :phone_number_id, references(:phone_numbers, type: :string, on_delete: :delete_all),
        null: false

      add :contact_wa_id,
          references(:contacts, column: :wa_id, type: :string, on_delete: :delete_all),
          null: false

      add :window_expires_at, :utc_datetime_usec
      add :typing_until, :utc_datetime_usec
      add :unread_count, :integer, null: false, default: 0
      add :last_message_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:conversations, [:phone_number_id, :contact_wa_id])

    create table(:messages) do
      add :wamid, :string, null: false
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :direction, :string, null: false
      add :type, :string, null: false
      add :payload, :map, null: false
      add :status, :string, null: false
      add :errors, {:array, :map}
      add :context_wamid, :string
      add :planned_failure, :map
      add :chaos_tag, :string
      add :sent_at, :utc_datetime_usec
      add :delivered_at, :utc_datetime_usec
      add :read_at, :utc_datetime_usec
      add :failed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:messages, [:wamid])
    create index(:messages, [:conversation_id])
    create index(:messages, [:status])
  end
end
