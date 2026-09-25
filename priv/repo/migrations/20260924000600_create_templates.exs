defmodule Whelx.Repo.Migrations.CreateTemplates do
  use Ecto.Migration

  def change do
    create table(:templates, primary_key: false) do
      add :id, :string, primary_key: true
      add :waba_id, references(:wabas, type: :string, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :language, :string, null: false
      add :category, :string, null: false
      add :components, {:array, :map}, null: false
      add :status, :string, null: false
      add :rejected_reason, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:templates, [:waba_id, :name, :language])
  end
end
