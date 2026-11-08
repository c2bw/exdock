defmodule Exdock.Server.State.Domains.Nodes do
  @moduledoc "State transition boundary for cluster nodes."

  @behaviour Exdock.Server.State.Change.Behaviour

  alias Exdock.Runtime.Mutation
  alias Exdock.Runtime.Mutation.Payload.NodeSetting
  alias Exdock.Server.State
  alias Exdock.Server.State.Change.{Outcome, Plan}
  alias Exdock.Server.State.Storage.Cluster
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage.Nodes, as: NodeStorageFacade
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence

  @impl true
  def reload(%State{cluster: %Cluster{storage: storage} = cluster} = state) do
    storage =
      storage
      |> NodeStorageFacade.string_map()
      |> Enum.reduce(storage, fn {node, node_data}, acc ->
        NodeStorageFacade.set(acc, node, NodePersistence.reload_settings(node_data))
      end)

    %{state | cluster: %{cluster | storage: storage}}
  end

  @impl true
  def broadcast(%State{cluster: %Cluster{storage: storage}}),
    do: {NodeStorageFacade.string_map(storage), []}

  @impl true
  def plan(%State{} = state, %Mutation{action: :setting, data: %NodeSetting{} = data}) do
    mutation = %Mutation{domain: :nodes, action: :setting, data: data}
    Plan.persisted(__MODULE__, state, mutation)
  end

  @impl true
  def execute_persisted(
        %State{cluster: %Cluster{storage: %NodeStorage{} = storage} = cluster} = state,
        %Mutation{action: :setting, data: %NodeSetting{node: node, key: key, value: value}}
      ) do
    case NodeStorageFacade.update_setting(storage, node, key, value) do
      {:ok, updated_storage} ->
        Outcome.planned(
          %{state | cluster: %{cluster | storage: updated_storage}},
          [delayed: false, force: true],
          []
        )

      {:error, reason} ->
        {:error, reason}
    end
  end
end
