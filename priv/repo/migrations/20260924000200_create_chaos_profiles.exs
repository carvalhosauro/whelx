defmodule Whelx.Repo.Migrations.CreateChaosProfiles do
  use Ecto.Migration

  def change do
    create table(:chaos_profiles) do
      add :seed, :integer, null: false, default: 42
      add :preset, :string, null: false, default: "off"
      add :latency_min_ms, :integer, null: false, default: 0
      add :latency_max_ms, :integer, null: false, default: 0
      add :sync_error_rate, :float, null: false, default: 0.0
      add :sync_error_codes, {:array, :string}, null: false
      add :async_fail_rate, :float, null: false, default: 0.0
      add :async_fail_codes, {:array, :integer}, null: false
      add :reorder_rate, :float, null: false, default: 0.0
      add :duplicate_rate, :float, null: false, default: 0.0
      add :drop_rate, :float, null: false, default: 0.0
      add :batch_rate, :float, null: false, default: 0.0
      add :webhook_extra_delay_ms, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end
  end
end
