Code.require_file(Path.expand("../../build/project_config.exs", __DIR__))

defmodule ExdockClientRuntime.MixProject do
  use Mix.Project

  alias Exdock.Build.ProjectConfig

  def project do
    ProjectConfig.project(:exdock_client_runtime, :runtime_protocol,
      start_permanent: false,
      aliases: aliases(),
      deps: deps()
    )
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp deps do
    [
      {:exdock_protocol, path: "../exdock_client/exdock_protocol"},
      {:ex_docker_api, "~> 1.55"}
    ]
  end

  defp aliases do
    [
      precommit: ["compile --warnings-as-errors", "format"]
    ]
  end
end
