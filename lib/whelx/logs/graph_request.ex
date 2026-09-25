defmodule Whelx.Logs.GraphRequest do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "graph_requests" do
    field :method, :string
    field :path, :string
    field :query, :string
    field :request_headers, :map, default: %{}
    field :request_body, :string
    field :response_status, :integer
    field :response_body, :string
    field :duration_ms, :integer
    field :chaos_tag, :string
    field :internal_error, :boolean, default: false
    timestamps()
  end

  @fields [
    :method,
    :path,
    :query,
    :request_headers,
    :request_body,
    :response_status,
    :response_body,
    :duration_ms,
    :chaos_tag,
    :internal_error
  ]

  def changeset(request, attrs) do
    request |> cast(attrs, @fields) |> validate_required([:method, :path])
  end
end
