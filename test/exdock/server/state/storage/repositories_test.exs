defmodule Exdock.Server.State.Storage.RepositoriesTest do
  use Exdock.DataCase, async: false

  alias Exdock.Server.State
  alias Exdock.Server.State.Storage.Persistence.Repository, as: RepositoryPersistence
  alias Exdock.Server.State.Storage.Repositories
  alias Exdock.Domain.Repository
  alias Exdock.Domain.Repository.Metadata
  alias Exdock.TestFixtures.DomainRelease, as: ReleaseFixture

  test "list returns one repository per unique URL and defaults missing repositories" do
    stored_url = "https://github.com/openai/example"
    missing_url = "https://github.com/openai/missing"
    repositories = state_with_repository(stored_url).repositories

    assert [stored, missing] = Repositories.list(repositories, [stored_url, stored_url, missing_url])
    assert stored.url == stored_url
    assert missing.url == missing_url
    assert missing.metadata.state == :ok
  end

  test "get_repository_data returns a matching repository or default data" do
    stored_url = "https://github.com/openai/example"
    missing_url = "https://github.com/openai/missing"
    repositories = [Repository.default(stored_url)]

    assert Repositories.get_repository_data(repositories, stored_url).url == stored_url
    assert Repositories.get_repository_data(repositories, missing_url).url == missing_url
  end

  test "filter keeps repositories whose page state is included" do
    ok_url = "https://github.com/openai/example"
    rate_limited_url = "https://github.com/openai/rate-limited"
    error_url = "https://github.com/openai/error"

    repositories = %Repositories{
      repositories: %{
        ok_url => Repository.default(ok_url),
        rate_limited_url => repository_with_state(rate_limited_url, :rate_limit),
        error_url => repository_with_state(error_url, :error)
      }
    }

    assert [%Repository{url: ^rate_limited_url}] = Repositories.filter(repositories, [:rate_limit])
    assert [%Repository{url: ^error_url}] = Repositories.filter(Map.values(repositories.repositories), [:error])
  end

  test "releases_of flattens release lists from repository collections" do
    first_url = "https://github.com/openai/example"
    second_url = "https://github.com/openai/other"
    first = release(first_url, "v1.0.0")
    second = release(second_url, "v2.0.0")

    repositories = [
      persist_release!(Repository.default(first_url), first),
      persist_release!(Repository.default(second_url), second)
    ]

    assert Enum.map(Repositories.releases_of(repositories), & &1.version) == ["v1.0.0", "v2.0.0"]
  end

  defp state_with_repository(url) do
    %State{
      repositories: %Repositories{
        repositories: %{url => Repository.default(url)}
      }
    }
  end

  defp repository_with_state(url, state) do
    url
    |> Repository.default()
    |> Map.put(:metadata, Metadata.default() |> Metadata.set_state(state))
  end

  defp release(url, version) do
    ReleaseFixture.build(repository: url, version: version, time_released: DateTime.utc_now())
  end

  defp persist_release!(repository, release) do
    {:ok, repository} = RepositoryPersistence.add_release(repository, release)
    repository
  end
end
