defmodule Exdock.Server.State.Domains.Repositories do
  @moduledoc "State transition boundary for release repositories."

  @behaviour Exdock.Server.State.Change.Behaviour

  alias Exdock.Runtime.Mutation
  alias Exdock.Runtime.Mutation.Payload.RepositoryReleases
  alias Exdock.Runtime.Projection
  alias Exdock.Server.State
  alias Exdock.Server.State.Change.{Outcome, Plan}
  alias Exdock.Server.State.Storage.Cluster
  alias Exdock.Server.State.Storage.Images
  alias Exdock.Server.State.Storage.Repositories
  alias Exdock.Server.State.Storage.Repositories.ReleaseImport

  @impl true
  def reload(%State{} = state), do: state

  @impl true
  def broadcast(%State{repositories: repositories, cluster: %Cluster{storage: storage}}) do
    data =
      repositories
      |> Repositories.list(Images.repositories_urls(storage))
      |> Projection.repositories()

    {data, []}
  end

  @impl true
  def plan(%State{} = state, %Mutation{action: :repository_releases, data: %RepositoryReleases{} = data}) do
    Plan.persisted(__MODULE__, state, %Mutation{
      domain: :repositories,
      action: :repository_releases,
      data: data
    })
  end

  @impl true
  def execute_persisted(
        %State{repositories: repositories} = state,
        %Mutation{action: :repository_releases, data: %RepositoryReleases{results: results}}
      ) do
    case ReleaseImport.apply(repositories, results) do
      {:ok, repositories} -> Outcome.planned(%{state | repositories: repositories}, [], [])
      {:error, reason} -> {:error, {:repository_persistence, reason}}
    end
  end
end
