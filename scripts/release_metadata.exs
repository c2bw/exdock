Code.require_file("../build/project_config.exs", __DIR__)
Code.require_file("../lib/exdock_client/exdock_protocol/lib/exdock/protocol/compatibility.ex", __DIR__)

defmodule Exdock.ReleaseMetadata do
  @moduledoc false
  alias Exdock.Build.ProjectConfig
  alias Exdock.Protocol.Compatibility

  def write!(destination) do
    root = Path.expand("..", __DIR__)
    File.cd!(root)
    version = ProjectConfig.project(:exdock, :control_plane, []) |> Keyword.fetch!(:version)
    {:ok, _} = Version.parse(version)
    unless Regex.match?(~r/^\d+\.\d+\.\d+$/, version), do: raise("Publication currently requires a stable x.y.z version")
    tag = "v" <> version
    ref = System.get_env("GITHUB_REF", "")

    if String.starts_with?(ref, "refs/tags/") and ref != "refs/tags/#{tag}",
      do: raise("Release tag must be #{tag}, matching the package version")

    repository = System.get_env("GITHUB_REPOSITORY", "local/exdock") |> String.downcase()

    unless Regex.match?(~r/^[a-z0-9][a-z0-9_.-]*\/[a-z0-9][a-z0-9_.-]*$/, repository),
      do: raise("Invalid repository name")

    {revision, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    revision = String.trim(revision)
    {status, 0} = System.cmd("git", ["status", "--porcelain"])
    dirty = status != ""
    image_revision = revision <> if(dirty, do: "-dirty", else: "")

    if System.get_env("GITHUB_ACTIONS") == "true" and dirty,
      do: raise("Release checkout must be clean")

    if System.get_env("GITHUB_SHA", revision) != revision,
      do: raise("Checkout does not match GITHUB_SHA")

    [_, notes] = String.split(File.read!("CHANGELOG.md"), "\n## [#{version}]\n", parts: 2)
    notes = notes |> String.split("\n## [", parts: 2) |> hd() |> String.trim()
    unless notes != "", do: raise("Release requires changelog notes")
    source = "https://github.com/" <> repository
    prefix = "ghcr.io/" <> repository

    metadata = %{
      "schema_version" => 1,
      "version" => version,
      "tag" => tag,
      "repository" => repository,
      "source" => source,
      "revision" => revision,
      "image_revision" => image_revision,
      "dirty" => dirty,
      "platform" => "linux/amd64",
      "packages" => %{
        "server" => version,
        "agent" => ProjectConfig.project(:exdock_client, :control_plane, []) |> Keyword.fetch!(:version),
        "runtime" => ProjectConfig.project(:exdock_client_runtime, :runtime_protocol, []) |> Keyword.fetch!(:version),
        "protocol" => ProjectConfig.project(:exdock_protocol, :runtime_protocol, []) |> Keyword.fetch!(:version)
      },
      "compatibility" => %{
        "wire" => Compatibility.wire_version(),
        "agent" => Compatibility.agent_version(),
        "agent_requirement" => Compatibility.agent_requirement(),
        "runtime_bundle" => Compatibility.runtime_bundle_version()
      },
      "base_images" => base_images!(),
      "image_tags" => %{"server" => prefix <> ":" <> tag, "agent" => prefix <> "_client:" <> tag}
    }

    File.mkdir_p!(destination)
    File.write!(Path.join(destination, "release.json"), JSON.encode!(metadata) <> "\n")
    File.write!(Path.join(destination, "release-notes.md"), notes <> "\n")

    if output = System.get_env("GITHUB_OUTPUT") do
      File.write!(output, "version=#{version}\nimage_revision=#{image_revision}\nsource=#{source}\n", [:append])
    end

    IO.puts("Prepared #{tag} metadata for #{repository} (dirty=#{dirty}); nothing published")
  end

  defp base_images! do
    images =
      for path <- ["Dockerfile", "lib/exdock_client/Dockerfile"] do
        content = File.read!(path)

        for key <- ["BUILDER_IMAGE", "RUNNER_IMAGE"], into: %{} do
          [_, reference] = Regex.run(~r/^ARG #{key}="([^"]+)"$/m, content)
          unless Regex.match?(~r/@sha256:[a-f0-9]{64}$/, reference), do: raise("#{path}: unpinned #{key}")
          {key, reference}
        end
      end

    [server, agent] = images
    unless server == agent, do: raise("Server and agent must use the same pinned bases")
    server
  end
end

case System.argv() do
  [destination] -> Exdock.ReleaseMetadata.write!(Path.expand(destination))
  _ -> raise("Usage: elixir scripts/release_metadata.exs OUTPUT_DIRECTORY")
end
