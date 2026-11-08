# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :exdock,
  ecto_repos: [Exdock.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: false],
  docker_engine_adapter: Exdock.Docker.Engine.Local,
  state_effect_runner: Exdock.Server.State.EffectRunner,
  tcp_max_frame_size: 16 * 1024 * 1024,
  login_rate_limit: [max_attempts: 100, window_ms: 5 * 60_000],
  trusted_proxy_ips: []

# Configure the endpoint
config :exdock, ExdockWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ExdockWeb.ErrorHTML, json: ExdockWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Exdock.PubSub,
  live_view: [signing_salt: "IfDz1zDj"]

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

config :phoenix_live_view, :colocated_assets, disable_symlink_warning: true

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  exdock: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  exdock: [
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

# Use Jason for Jason parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
