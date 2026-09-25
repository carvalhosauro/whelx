defmodule Whelx.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      WhelxWeb.Telemetry,
      Whelx.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:whelx, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:whelx, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Whelx.PubSub},
      {Oban, Application.fetch_env!(:whelx, Oban)},
      Whelx.Chaos.Counter,
      # Start to serve requests, typically the last entry
      WhelxWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Whelx.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      maybe_bootstrap()
      {:ok, pid}
    end
  end

  defp maybe_bootstrap do
    if Application.get_env(:whelx, :bootstrap, false) do
      try do
        Whelx.Accounts.bootstrap!()
      rescue
        error ->
          Logger.warning(
            "whelx bootstrap skipped: #{Exception.message(error)} (run mix ecto.migrate)"
          )
      end
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WhelxWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
