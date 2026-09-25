defmodule Whelx.Repo.Migrations.CreateGraphRequests do
  use Ecto.Migration

  def change do
    create table(:graph_requests) do
      add :method, :string, null: false
      add :path, :string, null: false
      add :query, :text
      add :request_headers, :map
      add :request_body, :text
      add :response_status, :integer
      add :response_body, :text
      add :duration_ms, :integer
      add :chaos_tag, :string
      add :internal_error, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:graph_requests, [:inserted_at])
  end
end
