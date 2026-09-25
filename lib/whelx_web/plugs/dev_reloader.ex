defmodule WhelxWeb.Plugs.DevReloader do
  @moduledoc """
  Dev-only: runs `Phoenix.CodeReloader` and the repo status check for the UI
  and control API, but not for Graph API traffic. The code reloader serializes
  requests on a global lock, which turns a 75 msg/s campaign into
  a queue of timeouts.
  """
  @behaviour Plug

  @impl true
  def init(opts) do
    %{
      reloader: Phoenix.CodeReloader.init(opts),
      repo_status: Phoenix.Ecto.CheckRepoStatus.init(otp_app: :whelx)
    }
  end

  @impl true
  def call(conn, opts) do
    if graph_path?(conn.path_info) do
      conn
    else
      conn
      |> Phoenix.CodeReloader.call(opts.reloader)
      |> Phoenix.Ecto.CheckRepoStatus.call(opts.repo_status)
    end
  end

  @doc false
  def graph_path?(["_media" | _]), do: true
  def graph_path?([version | _]), do: Regex.match?(~r/^v\d+\.\d+$/, version)
  def graph_path?(_), do: false
end
