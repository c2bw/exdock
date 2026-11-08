defmodule Exdock.Runtime.MutationContract.Containers do
  @moduledoc false

  alias Exdock.Domain.Container.Resources.Record
  alias Exdock.Runtime.Mutation.Payload

  @policies [:enabled, :disabled, :passthrough]

  @spec normalize(term(), term()) :: {:ok, term()} | {:error, term()}
  def normalize(:auto_update, {node, name, policy}),
    do: normalize(:auto_update, %Payload.ContainerAutoUpdate{node: node, name: name, policy: policy})

  def normalize(
        :auto_update,
        %Payload.ContainerAutoUpdate{node: node, name: name, policy: policy} = payload
      )
      when is_binary(node) and is_binary(name) and policy in @policies,
      do: {:ok, payload}

  def normalize(:set_resources, {node, id, resources}),
    do: normalize(:set_resources, %Payload.ContainerResources{node: node, id: id, resources: resources})

  def normalize(
        :set_resources,
        %Payload.ContainerResources{node: node, id: id, resources: %Record{}} = payload
      )
      when is_binary(node) and is_binary(id),
      do: {:ok, payload}

  def normalize(:set_logs, {node, id, logs, %DateTime{} = occurred_at}),
    do: normalize(:set_logs, %Payload.ContainerLogs{node: node, id: id, logs: logs, occurred_at: occurred_at})

  def normalize(
        :set_logs,
        %Payload.ContainerLogs{node: node, id: id, logs: logs, occurred_at: %DateTime{}} = payload
      )
      when is_binary(node) and is_binary(id) and is_list(logs) do
    if Enum.all?(logs, &is_binary/1), do: {:ok, payload}, else: invalid(:set_logs)
  end

  def normalize(:priority, priority = {_node, _name, _value}),
    do: normalize(:priority, [priority])

  def normalize(:priority, %Payload.ContainerPriorities{priorities: priorities}),
    do: normalize(:priority, priorities)

  def normalize(:priority, priorities) when is_list(priorities) do
    case Exdock.Result.traverse(priorities, &normalize_priority/1) do
      {:ok, normalized} -> {:ok, %Payload.ContainerPriorities{priorities: normalized}}
      {:error, _reason} -> invalid(:priority)
    end
  end

  def normalize(action, _payload), do: invalid(action)

  defp normalize_priority(%Payload.ContainerPriority{node: node, name: name, priority: priority} = payload)
       when is_binary(node) and is_binary(name) and is_integer(priority),
       do: {:ok, payload}

  defp normalize_priority({node, name, priority})
       when is_binary(node) and is_binary(name) and is_integer(priority),
       do: {:ok, %Payload.ContainerPriority{node: node, name: name, priority: priority}}

  defp normalize_priority(_value), do: {:error, :invalid}

  defp invalid(action), do: {:error, {:invalid_mutation_payload, :containers, action}}
end
