defmodule Exdock.Server.State.Domains.Containers do
  @moduledoc "State transition boundary for Docker container state."

  @behaviour Exdock.Server.State.Change.Behaviour

  alias Exdock.Runtime.Mutation

  alias Exdock.Runtime.Mutation.Payload.{
    ContainerAutoUpdate,
    ContainerLogs,
    ContainerPriorities,
    ContainerPriority,
    ContainerResources
  }

  alias Exdock.Server.State
  alias Exdock.Server.State.Change.{Outcome, Plan}
  alias Exdock.Server.State.Storage.Cluster
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage.Containers
  alias Exdock.Server.State.Storage.Containers.SettingsMutation
  alias Exdock.Domain
  alias Exdock.Server.Logging.AppendEntry

  @impl true
  def reload(%State{tags: tags, cluster: %Cluster{storage: storage} = cluster} = state) do
    put_storage(state, cluster, Containers.reload_configuration(storage, tags, false))
  end

  @doc false
  def reload_settings(%State{tags: tags, cluster: %Cluster{storage: storage} = cluster} = state) do
    put_storage(state, cluster, Containers.reload_configuration(storage, tags, true))
  end

  @impl true
  def broadcast(%State{cluster: %Cluster{storage: storage}}), do: {Containers.string_map(storage), []}

  @impl true
  def plan(%State{} = state, %Mutation{action: :auto_update, data: %ContainerAutoUpdate{} = data}) do
    Plan.persisted(__MODULE__, state, %Mutation{
      domain: :containers,
      action: :auto_update,
      data: data
    })
  end

  def plan(
        %State{cluster: %Cluster{storage: %NodeStorage{} = storage} = cluster} = state,
        %Mutation{
          action: :set_resources,
          data: %ContainerResources{node: node, id: id, resources: resources}
        }
      ) do
    storage =
      Containers.update_runtime_data(storage, node, id, fn container ->
        Domain.Container.set_resources(container, resources)
      end)

    Plan.immediate(changed_state(state, cluster, storage, delayed: true, delay_ms: 750))
  end

  def plan(
        %State{cluster: %Cluster{storage: %NodeStorage{} = storage} = cluster} = state,
        %Mutation{
          action: :set_logs,
          data: %ContainerLogs{node: node, id: id, logs: logs, occurred_at: occurred_at}
        }
      ) do
    storage =
      Containers.update_runtime_data(storage, node, id, fn container ->
        Domain.Container.set_logs(container, logs, occurred_at)
      end)

    Plan.immediate(changed_state(state, cluster, storage, delayed: false))
  end

  def plan(%State{} = state, %Mutation{action: :priority, data: %ContainerPriorities{} = data}) do
    Plan.persisted(__MODULE__, state, %Mutation{
      domain: :containers,
      action: :priority,
      data: data
    })
  end

  @impl true
  def execute_persisted(
        %State{cluster: %Cluster{storage: %NodeStorage{} = storage} = cluster} = state,
        %Mutation{
          action: :auto_update,
          data: %ContainerAutoUpdate{node: node, name: name, policy: auto_update}
        }
      ) do
    case SettingsMutation.apply_one(storage, node, name, :auto_update, auto_update) do
      {:ok, storage, messages} ->
        changed_state(
          state,
          cluster,
          storage,
          [delayed: false, force: true],
          logger_effects(messages)
        )

      {:error, reason} ->
        {:error, {:container_auto_update, reason}}
    end
  end

  def execute_persisted(
        %State{cluster: %Cluster{storage: %NodeStorage{} = storage} = cluster} = state,
        %Mutation{action: :priority, data: %ContainerPriorities{priorities: settings}}
      ) do
    priority_settings =
      Enum.map(settings, fn %ContainerPriority{node: node, name: name, priority: priority} ->
        {node, name, priority}
      end)

    case SettingsMutation.apply_priorities(storage, priority_settings) do
      {:ok, storage, messages} ->
        effects =
          logger_effects(messages) ++
            [{:log_entry, AppendEntry.new(:containers_priorities, {length(settings)})}]

        changed_state(state, cluster, storage, [delayed: false, force: true], effects)

      {:error, reason} ->
        {:error, {:container_priorities, reason}}
    end
  end

  defp changed_state(%State{} = state, %Cluster{} = cluster, %NodeStorage{} = storage, opts, effects \\ []) do
    Outcome.planned(put_storage(state, cluster, storage), opts, effects)
  end

  defp put_storage(%State{} = state, %Cluster{} = cluster, %NodeStorage{} = storage) do
    %{state | cluster: %{cluster | storage: storage}}
  end

  defp logger_effects(messages) when is_list(messages) do
    Enum.map(messages, &{:log, :info, &1})
  end
end
