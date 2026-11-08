defmodule Exdock.Server.Jobs.Local.ReleasesTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.Local.Releases
  alias Exdock.Server.Jobs.Local.Releases.HTTPRequest
  alias Exdock.Server.Jobs.Local.Releases.Plan
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Payload.ReleasesFetch, as: ReleasesPayload
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage.Repositories
  alias Exdock.Domain.Repository

  test "builds GitHub release API requests from repository URLs" do
    request = HTTPRequest.new("https://github.com/openai/example")

    assert request.provider == :github
    assert request.repo_name == "openai/example"
    assert request.repo_url == "https://github.com/openai/example"
    assert request.releases_url == "https://api.github.com/repos/openai/example/releases"
  end

  test "accepts repository URLs without HTTPS scheme" do
    request = HTTPRequest.new("http://github.com/openai/example")

    assert request.provider == :github
    assert request.repo_name == "openai/example"
    assert request.repo_url == "http://github.com/openai/example"
    assert request.releases_url == "https://api.github.com/repos/openai/example/releases"
  end

  test "includes configured GitHub bearer token in requests" do
    token_provider = fn :github -> "token-123" end

    assert %HTTPRequest{bearer_token: "token-123"} =
             HTTPRequest.new("https://github.com/openai/example", token_provider: token_provider)
  end

  test "accepts repository URLs without protocol" do
    request = HTTPRequest.new("github.com/openai/example")

    assert request.provider == :github
    assert request.repo_name == "openai/example"
    assert request.repo_url == "github.com/openai/example"
    assert request.releases_url == "https://api.github.com/repos/openai/example/releases"
  end

  test "normalizes surrounding whitespace and trailing slashes when building requests" do
    request = HTTPRequest.new("  https://github.com/openai/example/  ")

    assert request.provider == :github
    assert request.repo_name == "openai/example"
    assert request.repo_url == "  https://github.com/openai/example/  "
    assert request.releases_url == "https://api.github.com/repos/openai/example/releases"
  end

  test "exposes supported release providers" do
    assert MapSet.equal?(MapSet.new(HTTPRequest.providers()), MapSet.new(["github.com", "gitlab.com"]))
  end

  test "plans unique supported and unsupported repository URLs" do
    supported = Repository.default("https://github.com/openai/example")
    unsupported = Repository.default("https://example.com/openai/example")

    assert %{
             supported_urls: ["https://github.com/openai/example"],
             unsupported_urls: ["https://example.com/openai/example"]
           } = Plan.build([supported, unsupported, supported])
  end

  test "raises clearly for unsupported repository providers" do
    assert_raise RuntimeError, "Unsupported provider for repository: https://example.com/openai/example", fn ->
      HTTPRequest.new("https://example.com/openai/example")
    end
  end

  test "raises for provider URLs without repository paths" do
    assert_raise RuntimeError, "Unsupported provider for repository: https://github.com/", fn ->
      HTTPRequest.new("https://github.com/")
    end
  end

  test "builds GitLab release API requests with URL-encoded project paths" do
    request = HTTPRequest.new("https://gitlab.com/group/subgroup/example")

    assert request.provider == :gitlab
    assert request.repo_name == "group/subgroup/example"
    assert request.releases_url == "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fexample/releases"
  end

  test "parses GitHub releases into repository release structs" do
    request = HTTPRequest.new("https://github.com/openai/example")

    [release] =
      HTTPRequest.parse(request, [
        %{
          tag_name: "v1.0.0",
          html_url: "https://github.com/openai/example/releases/tag/v1.0.0",
          body: "Release notes",
          published_at: "2026-01-01T00:00:00Z"
        }
      ])

    assert release.source == :github
    assert release.repository == "https://github.com/openai/example"
    assert release.name == "openai/example"
    assert release.version == "v1.0.0"
    assert release.release_url == "https://github.com/openai/example/releases/tag/v1.0.0"
    assert :zlib.gunzip(release.compressed_description) == "Release notes"
  end

  test "parses GitHub releases with string keys from Req JSON responses" do
    request = HTTPRequest.new("https://github.com/gotenberg/gotenberg")

    [release] =
      HTTPRequest.parse(request, [
        %{
          "tag_name" => "v8.34.0",
          "html_url" => "https://github.com/gotenberg/gotenberg/releases/tag/v8.34.0",
          "body" => "Release notes",
          "published_at" => "2026-06-12T11:48:37Z"
        }
      ])

    assert release.source == :github
    assert release.repository == "https://github.com/gotenberg/gotenberg"
    assert release.name == "gotenberg/gotenberg"
    assert release.version == "v8.34.0"
    assert release.release_url == "https://github.com/gotenberg/gotenberg/releases/tag/v8.34.0"
    assert release.time_released == ~U[2026-06-12 11:48:37Z]
  end

  test "parses GitLab releases into repository release structs" do
    request = HTTPRequest.new("https://gitlab.com/group/example")

    [release] =
      HTTPRequest.parse(request, [
        %{
          tag_name: "v2.0.0",
          links: %{self: "https://gitlab.com/group/example/-/releases/v2.0.0"},
          description: "GitLab notes",
          released_at: "2026-02-01T00:00:00Z"
        }
      ])

    assert release.source == :gitlab
    assert release.repository == "https://gitlab.com/group/example"
    assert release.name == "group/example"
    assert release.version == "v2.0.0"
    assert release.release_url == "https://gitlab.com/group/example/-/releases/v2.0.0"
    assert :zlib.gunzip(release.compressed_description) == "GitLab notes"
  end

  test "parses GitLab releases with string keys from Req JSON responses" do
    request = HTTPRequest.new("https://gitlab.com/group/example")

    [release] =
      HTTPRequest.parse(request, [
        %{
          "tag_name" => "v2.0.0",
          "links" => %{"self" => "https://gitlab.com/group/example/-/releases/v2.0.0"},
          "description" => "GitLab notes",
          "released_at" => "2026-02-01T00:00:00Z"
        }
      ])

    assert release.source == :gitlab
    assert release.repository == "https://gitlab.com/group/example"
    assert release.name == "group/example"
    assert release.version == "v2.0.0"
    assert release.release_url == "https://gitlab.com/group/example/-/releases/v2.0.0"
    assert release.time_released == ~U[2026-02-01 00:00:00Z]
  end

  test "parses GitLab releases with mixed key types for nested link maps" do
    request = HTTPRequest.new("https://gitlab.com/group/example")

    [release] =
      HTTPRequest.parse(request, [
        %{
          "tag_name" => "v2.0.0",
          "links" => %{self: "https://gitlab.com/group/example/-/releases/v2.0.0"},
          "description" => "GitLab notes",
          "released_at" => "2026-02-01T00:00:00Z"
        }
      ])

    assert release.source == :gitlab
    assert release.repository == "https://gitlab.com/group/example"
    assert release.name == "group/example"
    assert release.version == "v2.0.0"
    assert release.release_url == "https://gitlab.com/group/example/-/releases/v2.0.0"
    assert release.time_released == ~U[2026-02-01 00:00:00Z]
  end

  test "summarize_results/1 separates status releases from fetch errors" do
    release_a = release("v1.0.0")
    release_b = release("v1.1.0")

    assert %{
             releases: [^release_a, ^release_b],
             errors: [{:error, "https://gitlab.com/group/missing", :not_found}]
           } =
             Releases.summarize_results([
               {:ok, "https://github.com/openai/example", [release_a, release_b]},
               {:error, "https://gitlab.com/group/missing", :not_found}
             ])
  end

  test "fetch_repositories builds release jobs from repository structs without trimming structs as URLs" do
    github_url = "https://github.com/influxdb"
    unsupported_url = "https://example.com/influxdb"
    previous_release = release("v0.9.0")

    state = %State{
      repositories: %Repositories{
        repositories: %{
          github_url => %{Repository.default(github_url) | releases: [previous_release]},
          unsupported_url => Repository.default(unsupported_url)
        }
      }
    }

    detail = Releases.fetch_repositories(state, [github_url, unsupported_url, github_url])

    assert %Jobs.Detail{name: :releases_fetch, spec_list: [{%Jobs.Spec{} = spec, _id}]} = detail
    assert %Jobs.Spec.Local{} = spec.location
    assert %ReleasesPayload{repositories: [github: "influxdb"], releases_list: [^previous_release]} = spec.data
  end

  test "fetch_repositories returns nil detail when all repositories are unsupported" do
    unsupported_url = "https://example.com/influxdb"

    state = %State{
      repositories: %Repositories{
        repositories: %{unsupported_url => Repository.default(unsupported_url)}
      }
    }

    assert Releases.fetch_repositories(state, [unsupported_url]) == nil
  end

  defp release(version) do
    Repository.Release.new(
      :github,
      "https://github.com/openai/example",
      "openai/example",
      version,
      "https://github.com/openai/example/releases/tag/#{version}",
      "Release notes",
      ~U[2026-01-01 00:00:00Z]
    )
  end
end
