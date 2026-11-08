defmodule Exdock.Server.State.Storage.Cluster.Persistence.Plan do
  @moduledoc """
  Durable delta between two cluster projections for one node.

  `nil` image/container sets mean their identities did not change and no
  deletion synchronization is required.
  """

  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage.Persistence.Container, as: ContainerPersistence
  alias Exdock.Server.State.Storage.Persistence.Image, as: ImagePersistence
  alias Exdock.Domain.{Container, Image, Node}

  defstruct node: nil,
            node_record: nil,
            image_ids: nil,
            images: [],
            container_names: nil,
            containers: []

  @type t :: %__MODULE__{
          node: String.t(),
          node_record: Node.t() | nil,
          image_ids: [String.t()] | nil,
          images: [Image.t()],
          container_names: [String.t()] | nil,
          containers: [Container.t()]
        }

  @spec build(map(), map(), String.t()) :: t()
  def build(
        %{storage: %NodeStorage{} = previous},
        %{storage: %NodeStorage{} = current},
        node
      )
      when is_binary(node) do
    previous_images = Storage.Images.list_node(previous, node)
    current_images = Storage.Images.list_node(current, node)
    previous_containers = Storage.Containers.list_node(previous, node)
    current_containers = Storage.Containers.list_node(current, node)

    images = changed_images(current_images, previous_images)
    containers = changed_containers(current_containers, previous_containers)
    image_ids = changed_identity_set(current_images, previous_images, & &1.id)
    container_names = changed_identity_set(current_containers, previous_containers, & &1.name)

    %__MODULE__{
      node: node,
      node_record: node_record(previous, current, node, images, containers, image_ids, container_names),
      image_ids: image_ids,
      images: images,
      container_names: container_names,
      containers: containers
    }
  end

  defp changed_images(current, previous) do
    previous_by_id = Map.new(previous, fn %Image{id: id} = image -> {id, image} end)

    Enum.reject(current, fn %Image{id: id} = image ->
      ImagePersistence.same?(image, Map.get(previous_by_id, id))
    end)
  end

  defp changed_containers(current, previous) do
    previous_by_name =
      Map.new(previous, fn %Container{name: name} = container -> {name, container} end)

    Enum.reject(current, fn %Container{name: name} = container ->
      ContainerPersistence.same?(container, Map.get(previous_by_name, name))
    end)
  end

  defp changed_identity_set(current, previous, identity) when is_function(identity, 1) do
    current_ids = MapSet.new(current, identity)

    if current_ids == MapSet.new(previous, identity) do
      nil
    else
      current_ids |> MapSet.to_list() |> Enum.sort()
    end
  end

  defp node_record(previous, current, node, images, containers, image_ids, container_names) do
    if first_snapshot?(previous, node) or durable_delta?(images, containers, image_ids, container_names) do
      Storage.Nodes.get(current, node)
    end
  end

  defp first_snapshot?(storage, node) do
    case Storage.Nodes.get(storage, node) do
      %Node{fetched_at: %DateTime{}} -> false
      _ -> true
    end
  end

  defp durable_delta?(images, containers, image_ids, container_names) do
    images != [] or containers != [] or not is_nil(image_ids) or not is_nil(container_names)
  end
end
