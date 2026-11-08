defmodule Exdock.Server.State.Storage.Nodes do
  @moduledoc """
  Cluster storage facade for node metadata.

  Runtime, persistence, and broadcast boundaries use durable string node IDs.

  The fetched timestamp is updated when a node refresh snapshot is accepted.
  """

  require Logger
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Domain
  alias Exdock.Domain.Node

  @spec list(NodeStorage.t()) :: list(String.t())
  def list(%NodeStorage{} = storage), do: NodeStorage.node_keys(storage)

  @doc """
  Return node data at the durable boundary.

  Nodes are keyed by validated strings inside state, and this facade preserves
  those durable keys for persistence and API boundaries.
  """
  @spec string_map(NodeStorage.t()) :: %{String.t() => Domain.Node.t()}
  def string_map(%NodeStorage{} = storage), do: NodeStorage.nodes_map(storage)

  @doc """
  Return all nodes from the current cluster state as a durable string-keyed map.
  """
  @spec full_string_map(map()) :: %{String.t() => Domain.Node.t()}
  def full_string_map(%{cluster: %{storage: %NodeStorage{} = storage}}), do: string_map(storage)

  @spec ordered_list(map()) :: list(String.t())
  def ordered_list(%{cluster: %{storage: %NodeStorage{} = storage}}) do
    storage
    |> list()
    |> Enum.sort()
  end

  @spec get(NodeStorage.t(), String.t()) :: Domain.Node.t() | nil
  def get(%NodeStorage{} = storage, node), do: NodeStorage.get_node(storage, node)

  @spec set(NodeStorage.t(), String.t(), Domain.Node.t()) :: NodeStorage.t()
  def set(%NodeStorage{} = storage, node, %Domain.Node{} = data),
    do: NodeStorage.put_node(storage, node, data)

  @spec make(NodeStorage.t(), String.t(), DateTime.t()) :: NodeStorage.t()
  def make(%NodeStorage{} = storage, node, %DateTime{} = fetched_at),
    do: update_fetch_time(storage, node, fetched_at)

  @spec update_fetch_time(NodeStorage.t(), String.t(), DateTime.t()) :: NodeStorage.t()
  def update_fetch_time(%NodeStorage{} = storage, node, %DateTime{} = fetched_at) do
    # Refreshing the node timestamp is the only thing this boundary updates for
    # a node-level refresh signal. The persistence plan decides whether that
    # refreshed node belongs in the durable delta.
    storage
    |> NodeStorage.update_node(
      node,
      Node.default(node),
      &Node.set_fetched_at(&1, fetched_at)
    )
  end

  @spec update_setting(NodeStorage.t(), String.t(), atom(), term()) ::
          {:ok, NodeStorage.t()} | {:error, term()}
  def update_setting(%NodeStorage{} = storage, node, key, value) do
    case get(storage, node) do
      %Domain.Node{} = node_data ->
        updated_node = put_node_setting(node_data, key, value)

        case persist_node_settings(updated_node, node) do
          :ok -> {:ok, set(storage, node, updated_node)}
          {:error, reason} -> {:error, {:node_setting_persistence, reason}}
        end

      nil ->
        {:error, {:node_setting_persistence, :node_not_found}}
    end
  end

  defp put_node_setting(%Domain.Node{} = node_data, key, value) do
    %Domain.Node{
      node_data
      | settings: Domain.Node.Settings.set(node_data.settings, key, value)
    }
  end

  defp persist_node_settings(%Domain.Node{settings: %Domain.Node.Settings{} = settings}, node) do
    case NodePersistence.insert_settings(settings, node) do
      {:ok, _settings} ->
        :ok

      {:error, error} ->
        Logger.error("Set node settings [#{node}]: #{inspect(error)}")
        {:error, error}
    end
  end
end
