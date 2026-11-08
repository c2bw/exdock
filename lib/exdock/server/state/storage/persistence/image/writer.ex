defmodule Exdock.Server.State.Storage.Persistence.Image.Writer do
  @moduledoc false

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.BatchWriter
  alias Exdock.Server.State.Storage.Persistence.ImageMetadata
  alias Exdock.Server.State.Storage.Persistence.Image.Mapper
  alias Exdock.Domain.Image, as: RuntimeImage
  alias Exdock.Domain.Image.Metadata

  @type node_id :: Exdock.NodeId.t()

  @spec same?(RuntimeImage.t(), RuntimeImage.t() | nil) :: boolean()
  def same?(%RuntimeImage{}, nil), do: false

  def same?(%RuntimeImage{} = left, %RuntimeImage{} = right) do
    Database.Image.same?(Mapper.database_record(left), Mapper.database_record(right))
  end

  @spec insert(RuntimeImage.t()) :: :ok | {:error, term()}
  def insert(%RuntimeImage{metadata: metadata, name: name} = image) do
    with :ok <- persist_metadata(metadata, name),
         :ok <- persist_record(image) do
      :ok
    end
  end

  @spec insert_many([RuntimeImage.t()]) :: :ok | {:error, term()}
  def insert_many(images) when is_list(images) do
    with :ok <- persist_metadata_many(images),
         :ok <- persist_image_rows(images) do
      :ok
    end
  end

  @doc """
  Marks the durable image rows missing from the latest node snapshot as deleted.
  """
  @spec sync_node_set(node_id(), [String.t()]) :: :ok | {:error, term()}
  def sync_node_set(node, image_ids)
      when is_binary(node) and is_list(image_ids) do
    node
    |> Database.Image.nodeset_update(image_ids)
    |> BatchWriter.sync_set(:image_set_sync)
  end

  defp persist_metadata(%Metadata{} = metadata, name) when is_binary(name) do
    if metadata.repository_url == "" and Exdock.ImageReference.image_id?(name) do
      :ok
    else
      metadata
      |> ImageMetadata.insert(name)
      |> Exdock.Server.State.Storage.Persistence.Result.normalize_insert_result(:metadata_insert)
    end
  end

  defp persist_metadata_many(images) do
    images
    |> Enum.uniq_by(& &1.name)
    |> BatchWriter.persist_each(fn %RuntimeImage{metadata: metadata, name: name} ->
      persist_metadata(metadata, name)
    end)
  end

  defp persist_record(%RuntimeImage{} = image) do
    image
    |> Mapper.database_record()
    |> Database.Image.insert()
    |> Exdock.Server.State.Storage.Persistence.Result.normalize_insert_result(:image_insert)
  end

  defp persist_image_rows(images) do
    BatchWriter.insert_rows(images, &Mapper.database_record/1, &Database.Image.insert_all/1, :image_insert_all)
  end
end
