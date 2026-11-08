[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{heex,ex,exs}",
    "{config,test,integration}/**/*.{heex,ex,exs}",
    "lib/exdock*.ex",
    "lib/exdock/**/*.{heex,ex,exs}",
    "lib/exdock_web/**/*.{heex,ex,exs}",
    "priv/*/seeds.exs",
    "scripts/**/*.{ex,exs}"
  ],
  line_length: 130
]
