defmodule Whelx.Repo.Migrations.CreateMedia do
  use Ecto.Migration

  def change do
    create table(:media_files, primary_key: false) do
      add :id, :string, primary_key: true
      add :mime_type, :string, null: false
      add :file_name, :string
      add :sha256, :string, null: false
      add :file_size, :integer, null: false
      add :path, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:upload_sessions, primary_key: false) do
      add :id, :string, primary_key: true
      add :app_id, :string, null: false
      add :file_name, :string, null: false
      add :file_length, :integer, null: false
      add :file_type, :string, null: false
      add :offset, :integer, null: false, default: 0
      add :handle, :string
      add :media_id, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:upload_sessions, [:handle])
  end
end
