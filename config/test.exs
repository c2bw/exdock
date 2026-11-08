import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :exdock, Exdock.Repo,
  database: Path.expand("../exdock_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :exdock, ExdockWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "saPeIe7vX2GdHI6NT+Wpqxvfg380drpbd3eZOJQEwfVpz39mW2CunlC6fMWRYTsA",
  server: false

config :exdock, :start_server, false

# Print only warnings and errors during test
config :logger, level: :warning

# Password behavior is covered in tests; production-strength derivation cost
# only makes the synchronous SQLite suite slower without increasing coverage.
config :pbkdf2_elixir, :rounds, 1

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
