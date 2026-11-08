defmodule Exdock.Server.State.Storage.Images do
  @moduledoc """
  Cluster storage facade for Docker images reported by client nodes.

  Image snapshots are rebuilt from client refresh results and merged with local
  metadata/settings. Cluster persistence compares completed snapshots after
  reconciliation.

  Storage, single-node operations, and broadcast payloads use validated string
  node identifiers throughout.
  """

  alias Exdock.Protocol.Snapshot, as: Client
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage.Persistence.Image, as: ImagePersistence
  alias Exdock.Domain.Image
  alias Exdock.Domain

  @doc """
  Get a list of all the images for all nodes.
  """
  @spec list(NodeStorage.t()) :: [Domain.Image.t()]
  def list(%NodeStorage{} = storage), do: NodeStorage.all_images(storage)

  @doc """
  Get a list of images of a node.
  """
  @spec list_node(NodeStorage.t(), Exdock.NodeId.t()) :: [Domain.Image.t()]
  def list_node(%NodeStorage{} = storage, node) when is_binary(node),
    do: NodeStorage.get_images(storage, node)

  @doc """
  Returns a list of unique repositories URLs.
  """
  @spec repositories_urls([Domain.Image.t()] | NodeStorage.t()) :: [String.t()]
  def repositories_urls(list) when is_list(list) do
    list
    |> Enum.map(&Image.get_repository/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def repositories_urls(%NodeStorage{} = s), do: s |> list() |> repositories_urls()

  @doc """
  Return images grouped by durable string key.

  This is the serialization/persistence boundary for string-based consumers.
  """
  @spec string_map(NodeStorage.t()) :: %{String.t() => [Domain.Image.t()]}
  def string_map(%NodeStorage{} = storage), do: NodeStorage.images_map(storage)

  @doc """
  Return all images for state with durable string keys.

  Use this where string node names are required.
  """
  @spec full_string_map(map()) :: %{String.t() => [Domain.Image.t()]}
  def full_string_map(%{cluster: %{storage: %NodeStorage{}}} = state),
    do: state.cluster.storage |> NodeStorage.images_map()

  @spec make(NodeStorage.t(), Exdock.NodeId.t(), list(Client.Image.t()), list(String.t())) :: NodeStorage.t()
  def make(%NodeStorage{} = s, node, images, used_ids)
      when is_binary(node) and is_list(images) and is_list(used_ids) do
    # The client snapshot is authoritative for Docker facts, while prior
    # in-memory images provide the durable metadata/settings to keep user
    # preferences stable across refreshes.
    previous_images = list_node(s, node)
    previous_images_by_id = Map.new(previous_images, &{&1.id, &1})
    used_image_ids = MapSet.new(used_ids)

    refreshed_images =
      Enum.map(images, &merge_client_image_snapshot(&1, node, previous_images_by_id, used_image_ids))

    set_node(s, node, refreshed_images)
  end

  defp merge_client_image_snapshot(
         %Client.Image{id: id} = client_image,
         node,
         previous_images_by_id,
         used_image_ids
       )
       when is_binary(node) and is_map(previous_images_by_id) and is_struct(used_image_ids, MapSet) do
    ImagePersistence.from_client(
      client_image,
      node,
      Map.get(previous_images_by_id, id),
      MapSet.member?(used_image_ids, id)
    )
  end

  @spec set_image(NodeStorage.t(), Exdock.NodeId.t(), Domain.Image.t()) :: NodeStorage.t()
  def set_image(%NodeStorage{} = s, node, %Image{id: to_set_id} = image) do
    previous_images = list_node(s, node)
    # Image setting changes target existing images from the current snapshot; a
    # missing image is left untouched until the next node refresh.
    refreshed_images = Enum.map(previous_images, &replace_image_if_id_matches(&1, to_set_id, image))
    set_node(s, node, refreshed_images)
  end

  @spec set_node(NodeStorage.t(), Exdock.NodeId.t(), list(Domain.Image.t())) :: NodeStorage.t()
  def set_node(%NodeStorage{} = storage, node, images) when is_binary(node) and is_list(images),
    do: NodeStorage.put_images(storage, node, images)

  @spec by_id(NodeStorage.t(), Exdock.NodeId.t(), String.t()) :: Domain.Image.t() | nil
  def by_id(%NodeStorage{} = s, node, image_id)
      when is_binary(node) and is_binary(image_id) do
    s
    |> list_node(node)
    |> find_image_by_id(image_id)
  end

  @spec by_digest(NodeStorage.t(), Exdock.NodeId.t(), String.t()) :: Domain.Image.t() | nil
  def by_digest(%NodeStorage{} = s, node, digest)
      when is_binary(node) and is_binary(digest) do
    s
    |> list_node(node)
    |> find_image_by_digest(digest)
  end

  @spec find_image_by_id([Domain.Image.t()], String.t()) :: Domain.Image.t() | nil
  defp find_image_by_id(images, id) when is_list(images) and is_binary(id),
    do: Enum.find(images, &match?(%Image{id: ^id}, &1))

  @spec find_image_by_digest([Domain.Image.t()], String.t()) :: Domain.Image.t() | nil
  defp find_image_by_digest(images, digest) when is_list(images) and is_binary(digest),
    do: Enum.find(images, &match?(%Image{digest: ^digest}, &1))

  defp replace_image_if_id_matches(%Image{id: id}, id, %Image{} = replacement), do: replacement
  defp replace_image_if_id_matches(%Image{} = image, _id, %Image{}), do: image

  @doc """
  Create the info for all the images.
  """
  @spec info(NodeStorage.t()) :: __MODULE__.Info.t()
  def info(%NodeStorage{} = s) do
    s
    |> list()
    |> __MODULE__.Info.new()
  end

  @doc """
  Create the info for all the images of a specific node.
  """
  @spec info(NodeStorage.t(), Exdock.NodeId.t()) :: __MODULE__.Info.t()
  def info(%NodeStorage{} = s, node) do
    s
    |> NodeStorage.get_images(node)
    |> __MODULE__.Info.new()
  end

  @spec reload_configuration(NodeStorage.t()) :: NodeStorage.t()
  def reload_configuration(%NodeStorage{} = s) do
    s
    |> NodeStorage.images_map()
    |> Enum.reduce(s, fn {node_key, images}, acc ->
      set_node(acc, node_key, Enum.map(images, &ImagePersistence.reload_configuration/1))
    end)
  end
end
