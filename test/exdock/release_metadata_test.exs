defmodule Exdock.ReleaseMetadataTest do
  use ExUnit.Case, async: true

  setup do
    directory = Path.join(System.tmp_dir!(), "exdock-release-metadata-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "records actual package and protocol versions with pinned bases", %{directory: directory} do
    assert {_output, 0} = prepare(directory, "refs/heads/main")
    metadata = directory |> Path.join("release.json") |> File.read!() |> JSON.decode!()
    assert metadata["tag"] == "v0.1.1"
    assert metadata["packages"] == %{"server" => "0.1.1", "agent" => "0.1.1", "runtime" => "0.1.0", "protocol" => "0.1.0"}

    assert metadata["compatibility"] == %{
             "wire" => 5,
             "agent" => "1.2.0",
             "agent_requirement" => "~> 1.2.0",
             "runtime_bundle" => "1"
           }

    assert metadata["platform"] == "linux/amd64"
    assert metadata["image_tags"]["server"] == "ghcr.io/example/exdock:v0.1.1"
    assert metadata["base_images"]["BUILDER_IMAGE"] =~ "@sha256:"
    assert metadata["base_images"]["RUNNER_IMAGE"] =~ "@sha256:"
    assert File.read!(Path.join(directory, "release-notes.md")) =~ "Initial public release"
  end

  test "rejects a tag that disagrees with the packages", %{directory: directory} do
    assert {output, status} = prepare(directory, "refs/tags/v9.9.9")
    assert status != 0
    assert output =~ "Release tag must be v0.1.1"
    refute File.exists?(Path.join(directory, "release.json"))
  end

  defp prepare(directory, ref) do
    System.cmd("elixir", ["scripts/release_metadata.exs", directory],
      stderr_to_stdout: true,
      env: [{"GITHUB_REPOSITORY", "Example/Exdock"}, {"GITHUB_REF", ref}, {"GITHUB_ACTIONS", "false"}, {"GITHUB_SHA", nil}]
    )
  end
end
