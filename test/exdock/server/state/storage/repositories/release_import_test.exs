defmodule Exdock.Server.State.Storage.Repositories.ReleaseImportTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Runtime.Mutation
  alias Exdock.Runtime.Mutation.Payload.RepositoryReleases
  alias Exdock.Server.State
  alias Exdock.Server.State.Domains.Repositories, as: RepositoriesDomain
  alias Exdock.Server.State.Change.{Outcome, Plan}
  alias Exdock.Server.State.Storage.Repositories
  alias Exdock.Domain.Repository
  alias Exdock.Domain.Repository.Metadata
  alias Exdock.TestFixtures.DomainRelease, as: ReleaseFixture

  test "known provider errors update repository metadata with the provider status" do
    url = "https://github.com/openai/example"
    state = state_with_repository(url)
    payload = releases_payload([{:error, url, :rate_limit}])

    %Outcome{state: %State{repositories: repositories}, broadcast_opts: [], effects: []} =
      RepositoriesDomain.plan(state, payload) |> Plan.execute()

    assert Repositories.page_state(repositories, url) == :rate_limit
  end

  test "unknown provider errors collapse to generic error metadata" do
    url = "https://github.com/openai/example"
    state = state_with_repository(url)
    payload = releases_payload([{:error, url, :connection_closed}])

    %Outcome{state: %State{repositories: repositories}, broadcast_opts: [], effects: []} =
      RepositoriesDomain.plan(state, payload) |> Plan.execute()

    assert Repositories.page_state(repositories, url) == :error
  end

  test "successful results add releases and record the fetch time" do
    url = "https://github.com/openai/example"
    state = state_with_repository(url)
    payload = releases_payload([{:ok, url, [release(url, "v1.0.0")]}])

    %Outcome{state: %State{repositories: repositories}, broadcast_opts: [], effects: []} =
      RepositoriesDomain.plan(state, payload) |> Plan.execute()

    assert [%Repository.Release{version: "v1.0.0"}] = Repositories.releases_of(repositories, url)

    assert %Repository{metadata: %Metadata{state: :ok, last_check: %DateTime{}}} =
             Map.fetch!(repositories.repositories, url)
  end

  test "successful empty results still record the fetch time" do
    url = "https://github.com/openai/empty"
    state = state_with_repository(url)
    payload = releases_payload([{:ok, url, []}])

    %Outcome{state: %State{repositories: repositories}, broadcast_opts: [], effects: []} =
      RepositoriesDomain.plan(state, payload) |> Plan.execute()

    assert %Repository{metadata: %Metadata{state: :ok, last_check: %DateTime{}}} =
             Map.fetch!(repositories.repositories, url)
  end

  test "unexpected result entries are ignored" do
    url = "https://github.com/openai/example"
    state = state_with_repository(url)
    payload = releases_payload([:unexpected, {:ok, url, :not_a_release_list}])

    %Outcome{state: %State{repositories: repositories}, broadcast_opts: [], effects: []} =
      RepositoriesDomain.plan(state, payload) |> Plan.execute()

    assert Repositories.releases_of(repositories, url) == []
    assert Repositories.page_state(repositories, url) == :ok
  end

  test "mixed results are applied in order" do
    success_url = "https://github.com/openai/example"
    rate_limited_url = "https://github.com/openai/rate-limited"
    unknown_error_url = "https://github.com/openai/unknown-error"

    state =
      %State{
        repositories: %Repositories{
          repositories: %{
            success_url => Repository.default(success_url),
            rate_limited_url => Repository.default(rate_limited_url),
            unknown_error_url => Repository.default(unknown_error_url)
          }
        }
      }

    payload =
      releases_payload([
        {:ok, success_url, [release(success_url, "v1.0.0")]},
        :unexpected,
        {:error, rate_limited_url, :rate_limit},
        {:error, unknown_error_url, :closed}
      ])

    %Outcome{state: %State{repositories: repositories}, broadcast_opts: [], effects: []} =
      RepositoriesDomain.plan(state, payload) |> Plan.execute()

    assert [%Repository.Release{version: "v1.0.0"}] = Repositories.releases_of(repositories, success_url)
    assert Repositories.page_state(repositories, rate_limited_url) == :rate_limit
    assert Repositories.page_state(repositories, unknown_error_url) == :error
  end

  test "a persistence failure rolls back the entire batch" do
    valid_url = "https://github.com/openai/valid"
    invalid_url = "https://github.com/openai/invalid"
    valid_release = release(valid_url, "v1.0.0")
    invalid_release = %{release(invalid_url, "v2.0.0") | release_url: nil}

    state =
      %State{
        repositories: %Repositories{
          repositories: %{
            valid_url => Repository.default(valid_url),
            invalid_url => Repository.default(invalid_url)
          }
        }
      }

    payload =
      releases_payload([
        {:ok, valid_url, [valid_release]},
        {:ok, invalid_url, [invalid_release]}
      ])

    assert {:error, {:repository_persistence, {:repository_release, %Ecto.Changeset{}}}} =
             RepositoriesDomain.plan(state, payload) |> Plan.execute()

    assert Database.Repository.load_all() == []
    assert Database.RepositoryRelease.load() == []
  end

  defp state_with_repository(url) do
    %State{
      repositories: %Repositories{
        repositories: %{url => Repository.default(url)}
      }
    }
  end

  defp releases_payload(results) do
    %Mutation{
      domain: :repositories,
      action: :repository_releases,
      data: %RepositoryReleases{results: results}
    }
  end

  defp release(url, version) do
    ReleaseFixture.build(repository: url, version: version, time_released: DateTime.utc_now())
  end
end
