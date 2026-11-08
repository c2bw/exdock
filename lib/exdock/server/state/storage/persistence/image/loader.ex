defmodule Exdock.Server.State.Storage.Persistence.Image.Loader do
  @moduledoc false

  alias Exdock.Protocol.Snapshot, as: Client
  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.Image.Mapper
  alias Exdock.Server.State.Storage.Persistence.ImageMetadata
  alias Exdock.Server.State.Storage.Persistence.ImageSettings
  alias Exdock.Domain.Image, as: RuntimeImage
  alias Exdock.Domain.Image.{Metadata, Settings}

  @type node_id :: Exdock.NodeId.t()

  @spec from_client(Client.Image.t(), node_id(), RuntimeImage.t() | nil, boolean()) ::
          RuntimeImage.t()
  def from_client(%Client.Image{} = image, node, %RuntimeImage{} = previous, in_use),
    do: RuntimeImage.from_client(image, node, previous, in_use)

  def from_client(%Client.Image{name: name, id: id} = image, node, nil, in_use) do
    metadata = ImageMetadata.load(name) || Metadata.default(name)
    settings = ImageSettings.load(node, id) || Settings.default()
    RuntimeImage.from_client(image, node, metadata, settings, in_use)
  end

  @spec load_metadata(RuntimeImage.t()) :: RuntimeImage.t()
  def load_metadata(%RuntimeImage{name: name} = image) do
    RuntimeImage.set_metadata(image, ImageMetadata.load(name) || Metadata.default(name))
  end

  @spec reload_configuration(RuntimeImage.t()) :: RuntimeImage.t()
  def reload_configuration(%RuntimeImage{node: node, id: id} = image) do
    image
    |> load_metadata()
    |> RuntimeImage.set_settings(ImageSettings.load(node, id) || Settings.default())
  end

  @spec digest_in_db?(node_id(), String.t()) :: boolean()
  def digest_in_db?(node, digest)
      when is_binary(node) and is_binary(digest),
      do: Database.Image.by_node_and_digest(node, digest) != nil

  @spec load_node(node_id()) :: {:ok, [RuntimeImage.t()]}
  def load_node(node) when is_binary(node) do
    image_ids = Database.Container.images_ids(node, false)
    images = Database.Image.by_node(node)
    {:ok, rehydrate_rows(images, image_ids, node)}
  end

  @spec load_id(node_id(), String.t()) :: {:ok, RuntimeImage.t() | :not_found}
  def load_id(node, id) when is_binary(node) and is_binary(id) do
    node
    |> Database.Image.by_node_and_id(id)
    |> load_row()
  end

  @spec load_digest(node_id(), String.t()) :: {:ok, RuntimeImage.t() | :not_found}
  def load_digest(node, digest)
      when is_binary(node) and is_binary(digest) do
    node
    |> Database.Image.by_node_and_digest(digest)
    |> load_row()
  end

  defp load_row(nil), do: {:ok, :not_found}

  defp load_row(%Database.Image.Record{node: node} = image) do
    loaded = rehydrate_rows([image], Database.Container.images_ids(node, false), node) |> List.first()
    {:ok, loaded}
  end

  defp rehydrate_rows(images, image_ids, node)
       when is_list(images) and is_list(image_ids) and is_binary(node) do
    metadata_by_name = ImageMetadata.load_names(Enum.map(images, & &1.name))
    settings_by_id = ImageSettings.load_node(node)

    Enum.map(images, &rehydrate(&1, image_ids, metadata_by_name, settings_by_id))
  end

  defp rehydrate(%Database.Image.Record{} = image, image_ids, metadata_by_name, settings_by_id) do
    metadata_name = Metadata.metadata_name(image.name)

    metadata = Map.get(metadata_by_name, metadata_name, Metadata.default(image.name))
    settings = Map.get(settings_by_id, image.id, Settings.default())
    attributes = Mapper.runtime_attributes(image, metadata, settings, image.id in image_ids)

    RuntimeImage.from_persisted(attributes)
  end
end
