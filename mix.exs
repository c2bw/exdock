Code.require_file("build/project_config.exs", __DIR__)

defmodule Exdock.MixProject do
  use Mix.Project

  alias Exdock.Build.ProjectConfig

  def project do
    ProjectConfig.project(:exdock, :control_plane,
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [flags: [:no_opaque], plt_add_apps: [:ex_unit, :exdock_client_runtime]],
      test_coverage: [
        summary: [threshold: 88],
        ignore_modules: coverage_ignored_modules()
      ],
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    )
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Exdock.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, "test.docker": :test, "test.release": :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: exdock_paths() ++ ["test/support"]
  defp elixirc_paths(_), do: exdock_paths()

  defp exdock_paths do
    ["lib/exdock", "lib/exdock.ex", "lib/exdock_web", "lib/exdock_web.ex"]
  end

  # Coverage includes orchestration and transport boundaries exercised by the
  # automated suite. OTP boot/release/database adapters and generated modules
  # without application-owned branches remain excluded.
  defp coverage_ignored_modules do
    [
      Exdock.Application,
      Exdock.Release,
      Exdock.Repo,
      Exdock.Server.Logging.Status.JobBehaviour,
      Exdock.Telemetry,
      ExdockWeb,
      ExdockWeb.CoreComponents,
      ExdockWeb.ErrorHTML,
      ExdockWeb.PageController,
      ExdockWeb.PageHTML,
      ExdockWeb.PageLive.LivePage.Use,
      ExdockWeb.UserSessionHTML,
      Inspect.Exdock.Accounts.User,
      ~r/^Elixir\.Jason\.Encoder\./
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:exdock_protocol, path: "lib/exdock_client/exdock_protocol"},
      {:exdock_client_runtime, path: "lib/exdock_client_runtime", only: :test, runtime: false},
      {:phoenix, "~> 1.8.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons, github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:pbkdf2_elixir, "~> 2.0"},
      {:ex_docker_api, "~> 1.55"},
      {:cloak_ecto, "~> 1.3.0"},
      {:crontab, "~> 1.1"},
      {:tz, "~> 0.28"},
      {:req, "~> 0.6.0"},
      {:mdex, "~> 0.13.5"},
      {:glasgow, "~> 0.1.4"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:regc, "~> 0.0.2"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "test.docker": ["cmd --cd lib/exdock_client env MIX_ENV=test mix run --no-start ../../integration/docker/run.exs"],
      "test.release": [
        "cmd --cd lib/exdock_client env MIX_ENV=test mix run --no-start ../../integration/docker/run.exs --release"
      ],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind exdock", "esbuild exdock"],
      "assets.deploy": [
        "compile",
        "tailwind exdock --minify",
        "esbuild exdock --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "xref graph --format cycles --label compile-connected --fail-above 0",
        "dialyzer",
        "deps.unlock --unused",
        "format",
        "cmd --cd lib/exdock_client/exdock_protocol mix precommit",
        "cmd --cd lib/exdock_client_runtime mix precommit",
        "cmd --cd lib/exdock_client mix precommit",
        "test --cover"
      ]
    ]
  end
end
