defmodule Exdock.Server.State.Storage.Containers.SettingsMutation do
  @moduledoc """
  Transactional container-setting reducer.

  Settings are persisted before the corresponding container projection is
  replaced. Bulk priority changes commit as one database transaction.
  """

  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage.Persistence.ContainerSettings
  alias Exdock.Server.State.Storage.Persistence.Transaction
  alias Exdock.Domain.Container

  @type setting :: :auto_update | :priority

  @spec apply_one(NodeStorage.t(), String.t(), String.t(), setting(), term()) ::
          {:ok, NodeStorage.t(), [String.t()]} | {:error, term()}
  def apply_one(%NodeStorage{} = storage, node, name, setting, value)
      when is_binary(node) and is_binary(name) and setting in [:auto_update, :priority] do
    case Storage.Containers.get_container(storage, node, name, :name) do
      nil ->
        {:error, :container_not_found}

      %Container{} = container ->
        updated_container = update_container(container, setting, value)

        case persist(updated_container, node, name) do
          :ok ->
            {:ok, Storage.Containers.set_container(storage, node, updated_container),
             [success_message(setting, node, name, value)]}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @spec apply_priorities(NodeStorage.t(), [{String.t(), String.t(), integer()}]) ::
          {:ok, NodeStorage.t(), [String.t()]} | {:error, term()}
  def apply_priorities(%NodeStorage{} = storage, changes) when is_list(changes) do
    case Transaction.run(fn -> Transaction.reduce(changes, storage, &apply_priority/2) end) do
      {:ok, updated_storage} ->
        messages =
          Enum.map(changes, fn {node, name, priority} ->
            success_message(:priority, node, name, priority)
          end)

        {:ok, updated_storage, messages}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_priority({node, name, priority}, current_storage)
       when is_binary(node) and is_binary(name) and is_integer(priority) do
    case apply_without_log(current_storage, node, name, :priority, priority) do
      {:ok, updated_storage} -> {:ok, updated_storage}
      {:error, reason} -> {:error, {:container_priority, node, name, reason}}
    end
  end

  defp apply_priority(invalid, _current_storage),
    do: {:error, {:invalid_container_priority, invalid}}

  defp apply_without_log(storage, node, name, setting, value) do
    case Storage.Containers.get_container(storage, node, name, :name) do
      nil ->
        {:error, :container_not_found}

      %Container{} = container ->
        updated_container = update_container(container, setting, value)

        case persist(updated_container, node, name) do
          :ok -> {:ok, Storage.Containers.set_container(storage, node, updated_container)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp update_container(%Container{} = container, :auto_update, value) do
    settings = container |> Container.get_settings() |> Container.Settings.set_auto_update(value)
    Container.set_settings(container, settings)
  end

  defp update_container(%Container{} = container, :priority, value) do
    settings = container |> Container.get_settings() |> Container.Settings.set_priority(value)
    Container.set_settings(container, settings)
  end

  defp persist(%Container{} = container, node, name) do
    case container |> Container.get_settings() |> ContainerSettings.insert(node, name) do
      {:ok, _record} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp success_message(:auto_update, node, name, value),
    do: "Set container auto_update: container=#{name} node=#{node} auto_update=#{value}"

  defp success_message(:priority, node, name, value),
    do: "Set container priority: container=#{name} node=#{node} priority=#{value}"
end
