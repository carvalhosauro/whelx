defmodule Whelx.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:apps, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false, default: "whelx"
      add :app_secret, :string, null: false
      add :verify_token, :string, null: false
      add :webhook_url, :string
      timestamps(type: :utc_datetime_usec)
    end

    create table(:wabas, primary_key: false) do
      add :id, :string, primary_key: true
      add :app_id, references(:apps, type: :string, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :subscribed, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:phone_numbers, primary_key: false) do
      add :id, :string, primary_key: true
      add :waba_id, references(:wabas, type: :string, on_delete: :delete_all), null: false
      add :display_phone_number, :string, null: false
      add :verified_name, :string, null: false
      add :quality_rating, :string, null: false, default: "GREEN"
      add :throughput_mps, :integer, null: false, default: 80
      timestamps(type: :utc_datetime_usec)
    end

    create index(:phone_numbers, [:waba_id])

    create table(:access_tokens, primary_key: false) do
      add :token, :string, primary_key: true
      add :waba_ids, {:array, :string}, null: false
      add :expires_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create table(:settings) do
      add :webhook_retry_profile, :string, null: false, default: "fast"
      add :template_approval_policy, :string, null: false, default: "manual"
      add :template_review_after_ms, :integer, null: false, default: 5000
      add :template_reject_reason, :string, null: false, default: "INVALID_FORMAT"
      add :sent_delay_ms, :integer, null: false, default: 300
      add :delivered_delay_ms, :integer, null: false, default: 700
      timestamps(type: :utc_datetime_usec)
    end
  end
end
