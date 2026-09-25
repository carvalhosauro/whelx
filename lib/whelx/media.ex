defmodule Whelx.Media do
  @moduledoc "Media binaries (inbound attachments, uploads) and resumable upload sessions."

  import Ecto.Query
  alias Whelx.{Ids, Repo}
  alias Whelx.Graph.Error
  alias Whelx.Media.{MediaFile, UploadSession}

  @max_upload 100_000_000

  @spec store(binary(), String.t(), String.t() | nil) :: {:ok, MediaFile.t()}
  def store(binary, mime_type, file_name \\ nil) do
    id = Ids.numeric_id()
    path = Path.join(media_dir(), id)
    File.mkdir_p!(media_dir())
    File.write!(path, binary)

    Repo.insert(%MediaFile{
      id: id,
      mime_type: mime_type,
      file_name: file_name,
      sha256: Base.encode64(:crypto.hash(:sha256, binary)),
      file_size: byte_size(binary),
      path: path
    })
  end

  def get_media(id), do: Repo.get(MediaFile, to_string(id))

  def read_binary(%MediaFile{path: path}), do: File.read(path)

  @spec url(MediaFile.t()) :: String.t()
  def url(%MediaFile{id: id}), do: Whelx.public_url() <> "/_media/" <> id

  def graph_json(%MediaFile{} = media) do
    %{
      "messaging_product" => "whatsapp",
      "url" => url(media),
      "mime_type" => media.mime_type,
      "sha256" => media.sha256,
      "file_size" => media.file_size,
      "id" => media.id
    }
  end

  # Resumable upload API

  def get_upload_session(id), do: Repo.get(UploadSession, id)

  def create_upload_session(app_id, params) do
    with {:ok, length} <- positive_int(params["file_length"], "file_length"),
         {:ok, type} <- present(params["file_type"], "file_type") do
      Repo.insert(%UploadSession{
        id: Ids.upload_session_id(),
        app_id: app_id,
        file_name: params["file_name"] || "upload",
        file_length: length,
        file_type: type
      })
    end
  end

  def append_upload(session_id, offset, binary) do
    case get_upload_session(session_id) do
      nil ->
        {:error, Error.unknown_object("post", session_id)}

      %UploadSession{offset: expected} when offset != expected ->
        {:error, Error.invalid_parameter("file_offset expected #{expected}, got #{offset}")}

      %UploadSession{} = session when session.offset + byte_size(binary) > session.file_length ->
        {:error,
         Error.invalid_parameter("upload exceeds file_length (#{session.file_length} bytes)")}

      %UploadSession{} = session ->
        path = upload_path(session)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, binary, [:append])
        finish_or_advance(session, session.offset + byte_size(binary), path)
    end
  end

  defp finish_or_advance(%UploadSession{file_length: length} = session, length, path) do
    {:ok, media} = store(File.read!(path), session.file_type, session.file_name)
    File.rm(path)

    session
    |> Ecto.Changeset.change(offset: length, handle: Ids.media_handle(), media_id: media.id)
    |> Repo.update()
  end

  defp finish_or_advance(session, offset, _path),
    do: session |> Ecto.Changeset.change(offset: offset) |> Repo.update()

  def handle_exists?(handle) when is_binary(handle),
    do: Repo.exists?(from s in UploadSession, where: s.handle == ^handle)

  def handle_exists?(_), do: false

  def get_by_handle(handle), do: Repo.get_by(UploadSession, handle: handle)

  @doc "Deletes files in the media dir that no longer have a DB row."
  def prune_orphan_files do
    known = MapSet.new(Repo.all(from m in MediaFile, select: m.id))

    case File.ls(media_dir()) do
      {:ok, files} ->
        files
        |> Enum.reject(&MapSet.member?(known, &1))
        |> Enum.each(&File.rm(Path.join(media_dir(), &1)))

      {:error, _} ->
        :ok
    end

    File.rm_rf(uploads_dir())
    :ok
  end

  defp media_dir, do: Path.join(Whelx.data_dir(), "media")
  defp uploads_dir, do: Path.join(Whelx.data_dir(), "uploads")

  defp upload_path(%UploadSession{id: id}),
    do: Path.join(uploads_dir(), String.replace(id, ~r/[^A-Za-z0-9_-]/, "_"))

  defp positive_int(value, field) do
    case Integer.parse(to_string(value)) do
      {int, ""} when int > 0 and int <= @max_upload ->
        {:ok, int}

      _ ->
        {:error, Error.invalid_parameter("#{field} is required and must be a positive integer")}
    end
  end

  defp present(value, _field) when is_binary(value) and value != "", do: {:ok, value}
  defp present(_value, field), do: {:error, Error.invalid_parameter("#{field} is required")}
end
