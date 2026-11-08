defmodule Exdock.Domain.RepositoryTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.Repository, as: RepositoryPersistence
  alias Exdock.Domain.Repository

  @url "https://github.com/openai/example"

  test "update_metadata/2 persists state and timestamp changes" do
    {:ok, repository} =
      @url
      |> Repository.default()
      |> RepositoryPersistence.update_metadata(:rate_limit)

    assert %Repository.Metadata{state: :rate_limit, last_check: %DateTime{}} = repository.metadata

    assert %Database.Repository{
             releases_page: :rate_limit,
             last_check: %DateTime{}
           } = Database.Repository.by_url(@url)
  end

  test "add_release/2 appends new releases and stores them" do
    release = release("v1.0.0", ~U[2026-06-01 00:00:00Z])

    {:ok, repository} =
      @url
      |> Repository.default()
      |> RepositoryPersistence.add_release(release)

    assert [%Repository.Release{version: "v1.0.0"}] = repository.releases
    assert [%Database.RepositoryRelease{version: "v1.0.0"}] = Database.RepositoryRelease.load(@url)
  end

  test "add_release/2 replaces an existing version and keeps newest releases first" do
    old = release("v1.0.0", ~U[2026-06-01 00:00:00Z], "Old notes")
    updated = release("v1.0.0", ~U[2026-06-03 00:00:00Z], "Updated notes")
    newer = release("v2.0.0", ~U[2026-06-04 00:00:00Z])

    repository = Repository.default(@url)
    {:ok, repository} = RepositoryPersistence.add_release(repository, old)
    {:ok, repository} = RepositoryPersistence.add_release(repository, newer)
    {:ok, repository} = RepositoryPersistence.add_release(repository, updated)

    assert Enum.map(repository.releases, & &1.version) == ["v2.0.0", "v1.0.0"]

    assert [%Database.RepositoryRelease{version: "v1.0.0", time_released: ~U[2026-06-03 00:00:00Z]}] =
             Database.RepositoryRelease.load(@url) |> Enum.filter(&(&1.version == "v1.0.0"))
  end

  test "load_all/0 restores persisted releases newest-first" do
    old = release("v1.0.0", ~U[2026-06-01 00:00:00Z])
    new = release("v2.0.0", ~U[2026-06-04 00:00:00Z])
    other_url = "https://gitlab.com/openai/other"
    other = release("v3.0.0", ~U[2026-06-05 00:00:00Z], "Other notes", other_url)

    repository = Repository.default(@url)
    {:ok, repository} = RepositoryPersistence.update_metadata(repository, :ok)
    {:ok, repository} = RepositoryPersistence.add_release(repository, old)
    {:ok, _repository} = RepositoryPersistence.add_release(repository, new)

    other_repository = Repository.default(other_url)
    {:ok, other_repository} = RepositoryPersistence.update_metadata(other_repository, :rate_limit)
    {:ok, _other_repository} = RepositoryPersistence.add_release(other_repository, other)

    attach_query_counter()

    repositories =
      RepositoryPersistence.load_all()
      |> Map.new(&{&1.url, &1})

    assert %Repository{metadata: %Repository.Metadata{state: :ok}, releases: releases} =
             Map.fetch!(repositories, @url)

    assert Enum.map(releases, & &1.version) == ["v2.0.0", "v1.0.0"]

    assert %Repository{
             metadata: %Repository.Metadata{state: :rate_limit},
             releases: [%Repository.Release{version: "v3.0.0"}]
           } = Map.fetch!(repositories, other_url)

    assert received_query_count() == 2
  end

  defp attach_query_counter do
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:exdock, :repo, :query],
        fn _event, _measurements, _metadata, test_pid ->
          send(test_pid, :repository_load_query)
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp received_query_count(count \\ 0) do
    receive do
      :repository_load_query -> received_query_count(count + 1)
    after
      0 -> count
    end
  end

  defp release(version, time_released, description \\ "Notes", repository_url \\ @url) do
    source = if String.starts_with?(repository_url, "https://gitlab.com"), do: :gitlab, else: :github

    Repository.Release.new(
      source,
      repository_url,
      "openai/example",
      version,
      "#{repository_url}/releases/#{version}",
      description,
      time_released
    )
  end
end
