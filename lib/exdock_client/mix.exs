Code.require_file(Path.expand("../../build/project_config.exs", __DIR__))

defmodule ExdockClient.MixProject do
  use Mix.Project

  alias Exdock.Build.ProjectConfig

  def project do
    ProjectConfig.project(:exdock_client, :control_plane,
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      # Application boot and the real SSL adapter are environment boundaries;
      # the connection state machine and its effects are measured here.
      test_coverage: [
        summary: [threshold: 75],
        ignore_modules: [ExdockClient.Application, Exdock.Client.Connection.Transport]
      ],
      deps: deps()
    )
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [extra_applications: [:logger, :hackney]] ++ application_callback(Mix.env())
  end

  defp application_callback(:test), do: []
  defp application_callback(_env), do: [mod: {ExdockClient.Application, []}]

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:exdock_protocol, path: "exdock_protocol"},
      {:exdock_client_runtime, path: "../exdock_client_runtime"},
      {:hackney, "~> 1.20"}
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
      setup: ["deps.get"],
      precommit: [
        "compile --warnings-as-errors",
        "format",
        "test --cover"
      ]
    ]
  end
end
