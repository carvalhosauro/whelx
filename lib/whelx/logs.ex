defmodule Whelx.Logs do
  @moduledoc "Log of every request received by the fake Graph API."

  import Ecto.Query
  alias Whelx.{Events, Repo}
  alias Whelx.Logs.GraphRequest

  @max_body 65_536

  def log_request(attrs) do
    with {:ok, request} <- %GraphRequest{} |> GraphRequest.changeset(attrs) |> Repo.insert() do
      Events.broadcast("requests", {:graph_request, request})
      {:ok, request}
    end
  end

  def list_requests(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    GraphRequest
    |> order_by(desc: :id)
    |> limit(^limit)
    |> filter_path(opts[:path])
    |> filter_since(opts[:since_id])
    |> Repo.all()
  end

  def get_request(id), do: Repo.get(GraphRequest, id)

  @doc "Number of 130429 (rate limit) responses since the given time."
  def count_rate_limited(%DateTime{} = since) do
    Repo.aggregate(
      from(r in GraphRequest,
        where: r.inserted_at >= ^since and like(r.response_body, "%130429%")
      ),
      :count
    )
  end

  @spec mask(String.t() | nil) :: String.t() | nil
  def mask(nil), do: nil

  def mask(token) when byte_size(token) > 12,
    do: String.slice(token, 0, 6) <> "…" <> String.slice(token, -4, 4)

  def mask(_token), do: "***"

  @spec truncate(String.t() | nil, pos_integer()) :: String.t() | nil
  def truncate(body, max \\ @max_body)
  def truncate(nil, _max), do: nil
  def truncate(body, max) when byte_size(body) <= max, do: body
  def truncate(body, max), do: binary_part(body, 0, max) <> "…[truncated]"

  defp filter_path(query, nil), do: query
  defp filter_path(query, ""), do: query
  defp filter_path(query, path), do: where(query, [r], like(r.path, ^"%#{path}%"))

  defp filter_since(query, nil), do: query
  defp filter_since(query, id), do: where(query, [r], r.id > ^id)
end
