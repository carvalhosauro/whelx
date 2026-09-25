defmodule Whelx.Repo.Migrations.AddOverridesPairLimitChaosScope do
  use Ecto.Migration

  def change do
    alter table(:wabas) do
      add :override_callback_uri, :string
      add :override_verify_token, :string
    end

    alter table(:phone_numbers) do
      add :override_callback_uri, :string
      add :override_verify_token, :string
    end

    alter table(:settings) do
      add :pair_rate_limit_enabled, :boolean, null: false, default: false
      add :pair_rate_limit_burst, :integer, null: false, default: 45
      add :pair_rate_limit_interval_ms, :integer, null: false, default: 6000
    end

    alter table(:chaos_profiles) do
      add :phone_number_ids, {:array, :string}
    end
  end
end
