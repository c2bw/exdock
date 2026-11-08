defmodule Exdock.Server.State.Storage.Repositories do
  @moduledoc """
  Stores repository metadata and release history keyed by repository URL.
  """
  alias Exdock.Server.State.Storage.Images
  alias Exdock.Server.State.Storage.Persistence.Repository, as: RepositoryPersistence
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Domain.Repository
  alias Exdock.Domain

  defstruct [
    :repositories
  ]

  @type t :: %__MODULE__{
          repositories: %{String.t() => Domain.Repository.t()}
        }

  @type raw_fetch_result ::
          {:ok, Domain.Repository.t(), [Domain.Repository.Release.t()]}
          | {:error, String.t(), term()}

  # Repository state is stored as a URL-keyed map so read paths are fast and all
  # writes are composed through explicit map updates.

  @spec load() :: t()
  def load() do
    %__MODULE__{
      repositories: load_repository_map()
    }
  end

  @doc """
    Add new releases to the state and database.
  """
  @spec add(t(), [Repository.Release.t()]) ::
          {:ok, t()} | {:error, {:repository_release, Ecto.Changeset.t()}}
  def add(%__MODULE__{} = repositories, releases) when is_list(releases) do
    Exdock.Result.reduce(releases, repositories, &store_release/2)
  end

  @doc """
  Persists a repository page state and refreshes the cached repository.
  """
  @spec update_metadata(t(), String.t(), Repository.Metadata.page_state()) ::
          {:ok, t()} | {:error, {:repository_metadata, Ecto.Changeset.t()}}
  def update_metadata(%__MODULE__{} = repositories, url, state) when is_binary(url) do
    update_repository(repositories, url, &RepositoryPersistence.update_metadata(&1, state))
  end

  defp store_release(%Repository.Release{repository: url} = release, %__MODULE__{} = repositories) do
    update_repository(repositories, url, &RepositoryPersistence.add_release(&1, release))
  end

  @spec update_repository(
          t(),
          String.t(),
          (Domain.Repository.t() -> {:ok, Domain.Repository.t()} | {:error, term()})
        ) :: {:ok, t()} | {:error, term()}
  defp update_repository(%__MODULE__{} = repositories, url, update_fn) when is_binary(url) and is_function(update_fn) do
    with {:ok, updated_repo} <- repositories |> repository(url) |> update_fn.() do
      {:ok, cache_repository(repositories, url, updated_repo)}
    end
  end

  @spec cache_repository(t(), String.t(), Domain.Repository.t()) :: t()
  defp cache_repository(%__MODULE__{repositories: repository_map} = repositories, url, %Repository{} = repo)
       when is_binary(url) do
    %{repositories | repositories: Map.put(repository_map, url, repo)}
  end

  @doc """
    Complete list of releases for a repository.
  """
  @spec releases_of(t(), String.t()) :: list(Domain.Repository.Release.t())
  def releases_of(%__MODULE__{repositories: r} = _, url) do
    r
    |> Map.get(url)
    |> repository_releases()
  end

  @spec releases_of(list(Domain.Repository.t())) :: list(Domain.Repository.Release.t())
  def releases_of(repositories) when is_list(repositories) do
    Enum.flat_map(repositories, fn %Domain.Repository{releases: releases} -> releases end)
  end

  # Preserve caller ordering while deduplicating repository URLs so repeated
  # image references resolve to one repository card.
  @spec list(t(), list(String.t())) :: list(Domain.Repository.t())
  def list(%__MODULE__{} = r, repository_urls) do
    repository_urls
    |> unique_repository_urls()
    |> Enum.map(&repository(r, &1))
  end

  @spec list(map()) :: list(Domain.Repository.t())
  def list(%{repositories: %__MODULE__{} = repositories, cluster: %{storage: %NodeStorage{} = storage}}) do
    repositories |> list(Images.repositories_urls(storage))
  end

  @spec get_repository_data(list(Domain.Repository.t()), String.t()) :: Domain.Repository.t()
  def get_repository_data(repositories, url) when is_list(repositories) and is_binary(url) do
    repository_from(repositories, url)
  end

  @doc """
  Get a repository by its URL, or return the default repository if not found.
  """
  @spec repository(t(), String.t()) :: Domain.Repository.t()
  def repository(%__MODULE__{repositories: repositories}, url) when is_binary(url) do
    Map.get_lazy(repositories, url, fn -> Domain.Repository.default(url) end)
  end

  @doc """
    Get the page status of a repository.
  """
  @spec page_state(t(), String.t()) :: Domain.Repository.Metadata.page_state()
  def page_state(%__MODULE__{} = repositories, url) do
    %Domain.Repository{metadata: %Repository.Metadata{state: state}} = repository(repositories, url)
    state
  end

  @doc """
    Filter repositories by returning only the ones for which the state is in the filter list.
  """
  @spec filter(t() | list(Repository.t()), list(Repository.Metadata.page_state())) :: list(Repository.t())
  def filter(%__MODULE__{repositories: repositories}, states) when is_list(states) do
    repositories
    |> Map.values()
    |> filter(states)
  end

  def filter(repositories, states) when is_list(repositories) and is_list(states) do
    Enum.filter(repositories, &state_in?(&1, states))
  end

  defp load_repository_map do
    RepositoryPersistence.load_all()
    |> Map.new(&repository_map_entry/1)
  end

  defp repository_map_entry(%Domain.Repository{url: url} = repo), do: {url, repo}

  # Preserve caller order while avoiding duplicate repository cards/jobs for
  # several images that point at the same upstream repository.
  defp unique_repository_urls(repository_urls), do: Enum.uniq(repository_urls)

  defp repository_from(repositories, url) when is_list(repositories) and is_binary(url) do
    Enum.find(repositories, Repository.default(url), &repository_url?(&1, url))
  end

  defp repository_url?(%Repository{url: repository_url}, url), do: repository_url == url

  defp repository_releases(nil), do: []
  defp repository_releases(%Domain.Repository{releases: releases}), do: releases

  defp state_in?(%Domain.Repository{metadata: %Repository.Metadata{state: state}}, states) do
    state in states
  end
end
