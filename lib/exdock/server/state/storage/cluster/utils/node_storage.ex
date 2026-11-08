defmodule Exdock.Server.State.Storage.Cluster.Utils.NodeStorage do
  @moduledoc """
  Typed in-memory cluster collections grouped by durable node ID.

  Nodes, images, and containers are separate fields and expose collection-
  specific functions, so callers cannot accidentally read or write a domain
  through another domain module's key.
  """

  alias Exdock.Domain
  alias Exdock.NodeId
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage.Data

  defstruct nodes: %Data{}, images: %Data{}, containers: %Data{}

  @type t :: %__MODULE__{
          nodes: Data.t(Domain.Node.t()),
          images: Data.t([Domain.Image.t()]),
          containers: Data.t([Domain.Container.t()])
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec get_node(t(), String.t()) :: Domain.Node.t() | nil
  def get_node(%__MODULE__{nodes: nodes}, node), do: Data.get(nodes, validate_node!(node))

  @spec put_node(t(), String.t(), Domain.Node.t()) :: t()
  def put_node(%__MODULE__{nodes: nodes} = storage, node, %Domain.Node{} = value),
    do: %{storage | nodes: Data.set(nodes, validate_node!(node), value)}

  @spec update_node(t(), String.t(), Domain.Node.t(), (Domain.Node.t() -> Domain.Node.t())) :: t()
  def update_node(%__MODULE__{} = storage, node, %Domain.Node{} = default, update_fn)
      when is_function(update_fn, 1) do
    next = storage |> get_node(node) |> value_or_default(default) |> update_fn.()
    put_node(storage, node, next)
  end

  @spec nodes_map(t()) :: %{String.t() => Domain.Node.t()}
  def nodes_map(%__MODULE__{nodes: nodes}), do: Data.get_map(nodes)

  @spec node_keys(t()) :: [String.t()]
  def node_keys(%__MODULE__{} = storage), do: storage |> nodes_map() |> Map.keys()

  @spec get_images(t(), String.t()) :: [Domain.Image.t()]
  def get_images(%__MODULE__{images: images}, node),
    do: Data.get(images, validate_node!(node)) || []

  @spec put_images(t(), String.t(), [Domain.Image.t()]) :: t()
  def put_images(%__MODULE__{images: images} = storage, node, values) when is_list(values),
    do: %{storage | images: Data.set(images, validate_node!(node), values)}

  @spec images_map(t()) :: %{String.t() => [Domain.Image.t()]}
  def images_map(%__MODULE__{images: images}), do: Data.get_map(images)

  @spec all_images(t()) :: [Domain.Image.t()]
  def all_images(%__MODULE__{} = storage),
    do: storage |> images_map() |> Map.values() |> Enum.flat_map(& &1)

  @spec get_containers(t(), String.t()) :: [Domain.Container.t()]
  def get_containers(%__MODULE__{containers: containers}, node),
    do: Data.get(containers, validate_node!(node)) || []

  @spec put_containers(t(), String.t(), [Domain.Container.t()]) :: t()
  def put_containers(%__MODULE__{containers: containers} = storage, node, values)
      when is_list(values),
      do: %{storage | containers: Data.set(containers, validate_node!(node), values)}

  @spec containers_map(t()) :: %{String.t() => [Domain.Container.t()]}
  def containers_map(%__MODULE__{containers: containers}), do: Data.get_map(containers)

  @spec all_containers(t()) :: [Domain.Container.t()]
  def all_containers(%__MODULE__{} = storage),
    do: storage |> containers_map() |> Map.values() |> Enum.flat_map(& &1)

  @spec remove(t(), String.t()) :: t()
  def remove(%__MODULE__{} = storage, node) when is_binary(node) do
    node = validate_node!(node)

    %{
      storage
      | nodes: Data.remove(storage.nodes, node),
        images: Data.remove(storage.images, node),
        containers: Data.remove(storage.containers, node)
    }
  end

  defp value_or_default(nil, default), do: default
  defp value_or_default(value, _default), do: value
  defp validate_node!(node), do: NodeId.normalize!(node)
end
