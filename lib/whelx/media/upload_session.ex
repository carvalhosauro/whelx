defmodule Whelx.Media.UploadSession do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "upload_sessions" do
    field :app_id, :string
    field :file_name, :string
    field :file_length, :integer
    field :file_type, :string
    field :offset, :integer, default: 0
    field :handle, :string
    field :media_id, :string
    timestamps()
  end
end
