defmodule Exdock.Server.State.Storage.Images.SettingsMutation do
  @moduledoc """
  Transactional image-setting mutations separated from snapshot projection.

  Persistence completes before the returned `NodeStorage` is changed, ensuring a
  rejected write cannot appear in the authoritative in-memory projection.
  """

  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage.Persistence.Image, as: ImagePersistence
  alias Exdock.Server.State.Storage.Persistence.ImageMetadata
  alias Exdock.Server.State.Storage.Persistence.ImageSettings
  alias Exdock.Server.State.Storage.Persistence.{BatchWriter, Result, Transaction}
  alias Exdock.Domain.Image

  @spec delete_lock(NodeStorage.t(), String.t(), String.t(), boolean()) ::
          {:ok, NodeStorage.t()} | {:error, term()}
  def delete_lock(%NodeStorage{} = storage, node, id, locked)
      when is_binary(node) and is_binary(id) and is_boolean(locked) do
    case Storage.Images.by_id(storage, node, id) do
      nil ->
        {:error, :image_not_found}

      %Image{settings: settings} = image ->
        updated_settings = Image.Settings.set_delete_lock(settings, locked)

        case ImageSettings.insert(updated_settings, node, id)
             |> Result.normalize_write_result(:image_settings_insert) do
          :ok ->
            {:ok, Storage.Images.set_image(storage, node, Image.set_settings(image, updated_settings))}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @spec repository_overrides(NodeStorage.t(), [{String.t(), String.t()}]) ::
          {:ok, NodeStorage.t()} | {:error, term()}
  def repository_overrides(%NodeStorage{} = storage, overrides) when is_list(overrides) do
    case Transaction.run(fn -> BatchWriter.persist_each(overrides, &persist_override/1) end) do
      {:ok, :ok} ->
        {:ok, reload_metadata(storage)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_override({name, url}) when is_binary(name) and is_binary(url) do
    (ImageMetadata.load(name) || Image.Metadata.default(name))
    |> Image.Metadata.set_repository_url(url)
    |> ImageMetadata.insert(name, on_conflict: :replace_all)
    |> Result.normalize_write_result(:image_metadata_upsert)
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, {:repository_override, name, reason}}
    end
  end

  defp persist_override(invalid), do: {:error, {:invalid_repository_override, invalid}}

  defp reload_metadata(%NodeStorage{} = storage) do
    storage
    |> NodeStorage.images_map()
    |> Enum.reduce(storage, fn {node, images}, current_storage ->
      Storage.Images.set_node(
        current_storage,
        node,
        Enum.map(images, &ImagePersistence.load_metadata/1)
      )
    end)
  end
end
