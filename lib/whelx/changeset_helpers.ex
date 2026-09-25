defmodule Whelx.ChangesetHelpers do
  @moduledoc "Changeset helpers shared by whelx schemas."
  import Ecto.Changeset

  @spec put_default(Ecto.Changeset.t(), atom(), (-> term())) :: Ecto.Changeset.t()
  def put_default(changeset, field, fun) do
    if get_field(changeset, field) in [nil, ""],
      do: put_change(changeset, field, fun.()),
      else: changeset
  end

  @spec validate_http_url(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_http_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and host not in [nil, ""] ->
          []

        _ ->
          [{field, "must be an http(s) URL"}]
      end
    end)
  end
end
