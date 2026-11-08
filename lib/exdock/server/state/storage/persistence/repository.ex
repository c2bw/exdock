defmodule Exdock.Server.State.Storage.Persistence.Repository do
  @moduledoc """
  Repository and mapper for repository metadata and release history.
  """

  require Logger

  alias Exdock.Database
  alias Exdock.Domain.Repository, as: RuntimeRepository
  alias Exdock.Domain.Repository.{Metadata, Release}
  alias Exdock.Server.State.Storage.Persistence.Repository.Mapper

  @spec load_all() :: [RuntimeRepository.t()]
  def load_all do
    releases_by_repository =
      Database.RepositoryRelease.load()
      |> Enum.map(&Release.from_persisted/1)
      |> Enum.group_by(& &1.repository)

    Database.Repository.load_all()
    |> Enum.map(&from_persisted(&1, releases_by_repository))
  end

  @spec load(String.t()) :: RuntimeRepository.t()
  def load(url) when is_binary(url) do
    %RuntimeRepository{
      url: url,
      metadata: load_metadata(url) || Metadata.default(),
      releases: load_releases(url)
    }
    |> sort_releases()
  end

  @spec update_metadata(RuntimeRepository.t(), Metadata.page_state()) ::
          {:ok, RuntimeRepository.t()} | {:error, {:repository_metadata, Ecto.Changeset.t()}}
  def update_metadata(
        %RuntimeRepository{
          url: url,
          metadata: %Metadata{state: old_state}
        } = repository,
        state
      ) do
    updated = RuntimeRepository.with_metadata_state(repository, state)

    case insert_metadata(updated.metadata, url) do
      {:ok, _row} ->
        log_metadata_state_change(url, old_state, updated.metadata.state)
        {:ok, updated}

      {:error, error} ->
        {:error, {:repository_metadata, error}}
    end
  end

  @spec add_release(RuntimeRepository.t(), Release.t()) ::
          {:ok, RuntimeRepository.t()} | {:error, {:repository_release, Ecto.Changeset.t()}}
  def add_release(%RuntimeRepository{} = repository, %Release{} = release) do
    stored_release = RuntimeRepository.matching_release(repository, release)

    case persist_release(stored_release, release) do
      {:ok, _row} -> {:ok, RuntimeRepository.put_release(repository, release)}
      {:error, error} -> {:error, {:repository_release, error}}
    end
  end

  @spec load_metadata(String.t()) :: Metadata.t() | nil
  def load_metadata(url) when is_binary(url) do
    case Database.Repository.by_url(url) do
      nil -> nil
      %Database.Repository{} = row -> Metadata.from_persisted(row)
    end
  end

  @spec load_all_metadata() :: [Metadata.t()]
  def load_all_metadata do
    Database.Repository.load_all()
    |> Enum.map(&Metadata.from_persisted/1)
  end

  @spec insert_metadata(Metadata.t(), String.t()) ::
          {:ok, Database.Repository.t()} | {:error, Ecto.Changeset.t()}
  def insert_metadata(%Metadata{} = metadata, url) when is_binary(url) do
    metadata
    |> Mapper.metadata_record(url)
    |> Database.Repository.insert()
  end

  defp load_releases(url) do
    url
    |> Database.RepositoryRelease.load()
    |> Enum.map(&Release.from_persisted/1)
  end

  defp from_persisted(%Database.Repository{url: url} = repository, releases_by_repository)
       when is_map(releases_by_repository) do
    %RuntimeRepository{
      url: url,
      metadata: Metadata.from_persisted(repository),
      releases: Map.get(releases_by_repository, url, [])
    }
    |> sort_releases()
  end

  @spec insert_if_different(Release.t() | nil, Release.t()) ::
          {:ok, Database.RepositoryRelease.t() | :same} | {:error, Ecto.Changeset.t()}
  def insert_if_different(stored, %Release{} = release) do
    persist_release(stored, release)
  end

  defp persist_release(nil, %Release{} = release), do: insert_release(release)

  defp persist_release(%Release{} = stored, %Release{} = release) do
    if same_database_release?(stored, release),
      do: {:ok, :same},
      else: insert_release(release)
  end

  defp insert_release(%Release{} = release) do
    release
    |> Mapper.release_record()
    |> Database.RepositoryRelease.insert()
  end

  defp same_database_release?(%Release{} = left, %Release{} = right) do
    Mapper.same_release?(left, right)
  end

  defp log_metadata_state_change(_url, state, state), do: :ok

  defp log_metadata_state_change(url, old_state, new_state) do
    Logger.info("Repository Page State url=#{url} old=#{old_state} new=#{new_state}")
  end

  defp sort_releases(%RuntimeRepository{releases: releases} = repository) do
    %{repository | releases: Enum.sort_by(releases, & &1.time_released, {:desc, DateTime})}
  end
end
