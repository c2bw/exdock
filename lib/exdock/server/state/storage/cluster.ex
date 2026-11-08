defmodule Exdock.Server.State.Storage.Cluster do
  @moduledoc """
  A wrapper to store and manage all the data retrieved from the nodes in the cluster.

  Data is managed "by node" using the `NodeStorage` module.
  The cluster itself is the in-memory projection of the latest node refreshes;
  reconciliation builds that projection before a separate persistence phase
  writes its durable delta.
  """
  alias Exdock.Server.State.Storage.Cluster.SnapshotCommit
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Persistence.Container, as: ContainerPersistence
  alias Exdock.Server.State.Storage.Persistence.Image, as: ImagePersistence
  alias Exdock.Server.State.Storage.Persistence.LoadReport
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Domain
  alias Exdock.Protocol.Snapshot, as: Client

  defstruct [
    :storage
  ]

  @type t :: %__MODULE__{
          storage: NodeStorage.t()
        }

  @spec new() :: t()
  def new() do
    %__MODULE__{
      storage: NodeStorage.new()
    }
  end

  @spec remove(t(), String.t()) :: t()
  def remove(%__MODULE__{storage: storage} = cluster, node) when is_binary(node) do
    %{cluster | storage: NodeStorage.remove(storage, node)}
  end

  @spec load(t(), String.t(), map()) :: {:ok, t()} | {:error, LoadReport.t(term())}
  def load(%__MODULE__{} = cluster, node, metadata) when is_map(metadata) do
    # Startup/reconnect seeds the in-memory node snapshot from persisted data.
    # The next client refresh becomes authoritative for Docker runtime state.
    with {:ok, storage} <- load_node_snapshot(cluster.storage, node, metadata) do
      {:ok, %{cluster | storage: storage}}
    end
  end

  @spec make(
          t(),
          String.t(),
          [Client.Container.t()],
          [Client.Image.t()],
          Storage.TagsInfo.t()
        ) :: {:ok, t()} | {:error, term()}
  def make(%__MODULE__{} = cluster, node, containers, images, %Storage.TagsInfo{} = tags_info)
      when is_binary(node) and is_list(containers) and is_list(images) do
    case SnapshotCommit.commit(
           cluster,
           node,
           containers,
           images,
           tags_info,
           DateTime.utc_now()
         ) do
      {:ok, %__MODULE__{} = updated_cluster} -> {:ok, updated_cluster}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec load_node_snapshot(NodeStorage.t(), String.t(), map()) ::
          {:ok, NodeStorage.t()} | {:error, LoadReport.t(term())}
  defp load_node_snapshot(%NodeStorage{} = storage, node, metadata)
       when is_binary(node) and is_map(metadata) do
    # Hydration is read-only; persisted rows seed the in-memory projection.
    platform = Map.fetch!(metadata, "platform")
    node_data = load_node(node) |> Domain.Node.put_metadata(metadata)

    with {:ok, images} <- ImagePersistence.load_node(node),
         {:ok, containers} <-
           ContainerPersistence.load_node(node, platform, false,
             node_data: node_data,
             images: images
           ) do
      {:ok,
       storage
       |> NodeStorage.put_node(node, node_data)
       |> NodeStorage.put_images(node, images)
       |> NodeStorage.put_containers(node, containers)}
    end
  end

  @spec load_node(String.t()) :: Domain.Node.t()
  defp load_node(node), do: NodePersistence.load(node) || Domain.Node.default(node)

  @spec has_node?(t(), String.t()) :: boolean()
  defp has_node?(%__MODULE__{storage: storage}, node), do: Storage.Nodes.get(storage, node) != nil

  # Read-only accessors for cluster-wide and node-specific snapshots.
  @spec info(map()) :: __MODULE__.Info.t()
  def info(%{cluster: %__MODULE__{} = cluster}) do
    __MODULE__.Info.new(cluster)
  end

  @spec data(map(), String.t()) :: __MODULE__.NodeData.t() | :not_found
  def data(%{cluster: %__MODULE__{} = cluster}, node)
      when is_binary(node) do
    case has_node?(cluster, node) do
      true -> __MODULE__.NodeData.new(cluster, node)
      false -> :not_found
    end
  end
end
