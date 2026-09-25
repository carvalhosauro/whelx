defmodule Whelx.Media.MediaFile do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "media_files" do
    field :mime_type, :string
    field :file_name, :string
    field :sha256, :string
    field :file_size, :integer
    field :path, :string
    timestamps()
  end
end
