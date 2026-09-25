# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :whelx,
  ecto_repos: [Whelx.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :whelx, WhelxWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WhelxWeb.ErrorHTML, json: WhelxWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Whelx.PubSub,
  live_view: [signing_salt: "xerAWJF2"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  whelx: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  whelx: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :whelx, Oban,
  engine: Oban.Engines.Lite,
  repo: Whelx.Repo,
  stage_interval: 250,
  queues: [default: 10, statuses: 20, webhooks: 20],
  plugins: [{Oban.Plugins.Pruner, max_age: 86_400}]

config :whelx,
  data_dir: Path.expand("../data", __DIR__),
  public_url: "http://localhost:4000",
  bootstrap: true,
  webhook_req_options: []

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
