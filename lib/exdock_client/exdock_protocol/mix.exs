project_config =
  ["../../build/project_config.exs", "../../../build/project_config.exs"]
  |> Enum.map(&Path.expand(&1, __DIR__))
  |> Enum.find(&File.exists?/1)

Code.require_file(project_config)

defmodule ExdockProtocol.MixProject do
  use Mix.Project

  alias Exdock.Build.ProjectConfig

  def project do
    ProjectConfig.project(:exdock_protocol, :runtime_protocol,
      start_permanent: false,
      aliases: aliases(),
      deps: [{:node_wire, git: "https://git.lan.mangekyo.live/scorpion/nodewire.git", branch: "main"}]
    )
  end

  def application, do: []

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp aliases do
    [precommit: ["compile --warnings-as-errors", "format"]]
  end
end
