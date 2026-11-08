defmodule Exdock.Server.State.Domains.Images do
  @moduledoc "State transition boundary for Docker image state."

  @behaviour Exdock.Server.State.Change.Behaviour

  alias Exdock.Runtime.Mutation
  alias Exdock.Runtime.Mutation.Payload.{ImageDeleteLock, ImageRepositories, ImageRepository}
  alias Exdock.Server.State
  alias Exdock.Server.State.Change.{Outcome, Plan}
  alias Exdock.Server.State.Storage.Cluster
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage.Images
  alias Exdock.Server.State.Storage.Images.SettingsMutation
  alias Exdock.Server.Logging.AppendEntry

  @forced_change_options [delayed: false, force: true]

  @impl true
  def reload(%State{cluster: %Cluster{storage: storage} = cluster} = state) do
    %{state | cluster: %{cluster | storage: Images.reload_configuration(storage)}}
  end

  @impl true
  def broadcast(%State{cluster: %Cluster{storage: storage}}), do: {Images.string_map(storage), []}

  @impl true
  def plan(%State{} = state, %Mutation{action: :delete_lock, data: %ImageDeleteLock{} = data}) do
    Plan.persisted(__MODULE__, state, %Mutation{domain: :images, action: :delete_lock, data: data})
  end

  def plan(%State{} = state, %Mutation{action: :repository_url, data: %ImageRepositories{} = data}) do
    Plan.persisted(__MODULE__, state, %Mutation{
      domain: :images,
      action: :repository_url,
      data: data
    })
  end

  @impl true
  def execute_persisted(
        %State{cluster: %Cluster{storage: %NodeStorage{} = storage}} = state,
        %Mutation{action: :delete_lock, data: %ImageDeleteLock{node: node, id: id, locked?: to_lock}}
      ) do
    case SettingsMutation.delete_lock(storage, node, id, to_lock) do
      {:ok, storage} -> forced_change(state, storage, [])
      {:error, reason} -> {:error, {:image_delete_lock, reason}}
    end
  end

  def execute_persisted(
        %State{cluster: %Cluster{storage: %NodeStorage{} = storage}} = state,
        %Mutation{action: :repository_url, data: %ImageRepositories{overrides: overrides}}
      ) do
    overrides = Enum.map(overrides, fn %ImageRepository{image: image, url: url} -> {image, url} end)

    case SettingsMutation.repository_overrides(storage, overrides) do
      {:ok, storage} ->
        effects =
          if overrides == [],
            do: [],
            else: [{:log_entry, AppendEntry.new(:repository_overrides, {length(overrides)})}]

        forced_change(state, storage, effects)

      {:error, reason} ->
        {:error, {:image_repository_overrides, reason}}
    end
  end

  defp forced_change(
         %State{cluster: %Cluster{} = cluster} = state,
         %NodeStorage{} = storage,
         effects
       ) do
    Outcome.planned(
      %{state | cluster: %{cluster | storage: storage}},
      @forced_change_options,
      effects
    )
  end
end
