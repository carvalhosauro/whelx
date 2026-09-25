import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/whelx start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :whelx, WhelxWeb.Endpoint, server: true
end

port = String.to_integer(System.get_env("PORT", "4000"))
config :whelx, WhelxWeb.Endpoint, http: [port: port]

parse_ip = fn value ->
  {:ok, ip} = value |> String.to_charlist() |> :inet.parse_address()
  ip
end

if config_env() != :test do
  config :whelx, public_url: System.get_env("WHELX_PUBLIC_URL", "http://localhost:#{port}")

  if data_dir = System.get_env("DATA_DIR") do
    config :whelx, data_dir: data_dir
  end
end

if config_env() == :dev and System.get_env("BIND_IP") do
  config :whelx, WhelxWeb.Endpoint, http: [ip: parse_ip.(System.get_env("BIND_IP")), port: port]
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :whelx, WhelxWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/whelx_web/router\.ex$",
        ~r"lib/whelx_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  data_dir = System.get_env("DATA_DIR", "/data")
  config :whelx, data_dir: data_dir

  config :whelx, Whelx.Repo,
    database: System.get_env("DATABASE_PATH") || Path.join(data_dir, "whelx.db"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "1")

  # whelx is a local test tool: a random key per boot is fine (it only signs
  # LiveView sessions). Set SECRET_KEY_BASE to keep sessions across restarts.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") || Base.encode64(:crypto.strong_rand_bytes(48))

  config :whelx, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :whelx, WhelxWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST", "localhost"), port: port, scheme: "http"],
    http: [ip: parse_ip.(System.get_env("BIND_IP", "0.0.0.0")), port: port],
    check_origin: false,
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :whelx, WhelxWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :whelx, WhelxWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
