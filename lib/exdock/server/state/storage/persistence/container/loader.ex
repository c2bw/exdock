defmodule Exdock.Server.State.Storage.Persistence.Container.Loader do
  @moduledoc false

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.ContainerSettings
  alias Exdock.Server.State.Storage.Persistence.Container.HydrationContext
  alias Exdock.Server.State.Storage.Persistence.Container.Mapper
  alias Exdock.Server.State.Storage.Persistence.Error, as: PersistenceError
  alias Exdock.Server.State.Storage.Persistence.LoadReport
  alias Exdock.Domain.Container, as: RuntimeContainer
  alias Exdock.Domain.Container.Settings
  alias Exdock.Domain.TagInfo

  require Logger

  @type node_id :: Exdock.NodeId.t()

  @spec load_node(node_id(), String.t(), boolean()) ::
          {:ok, [RuntimeContainer.t()]} | {:error, LoadReport.t(RuntimeContainer.t())}
  def load_node(node, platform, load_deleted \\ false)
      when is_binary(node) and is_binary(platform) and is_boolean(load_deleted) do
    load_node(node, platform, load_deleted, [])
  end

  @spec load_node(node_id(), String.t(), boolean(), keyword()) ::
          {:ok, [RuntimeContainer.t()]} | {:error, LoadReport.t(RuntimeContainer.t())}
  def load_node(node, platform, load_deleted, opts)
      when is_binary(node) and is_binary(platform) and
             is_boolean(load_deleted) and is_list(opts) do
    case Database.Container.load_node(node, load_deleted) do
      {:ok, rows} ->
        hydrate_rows(rows, node, platform, opts)

      {:error, reason} ->
        {:error, LoadReport.new(:container_load, reason)}
    end
  end

  @spec load(node_id(), String.t(), String.t(), boolean()) ::
          {:ok, RuntimeContainer.t() | :not_found} | {:error, term()}
  def load(node, container_name, platform, load_deleted \\ false)
      when is_binary(node) and is_binary(container_name) and
             is_binary(platform) and is_boolean(load_deleted) do
    case Database.Container.load(node, container_name, load_deleted) do
      {:ok, nil} ->
        {:ok, :not_found}

      {:ok, %Database.Container.Record{} = row} ->
        with {:ok, context} <- HydrationContext.load(node, platform, []) do
          compose(row, context)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec reload_settings(RuntimeContainer.t()) :: RuntimeContainer.t()
  def reload_settings(%RuntimeContainer{node: node, name: name} = container) do
    RuntimeContainer.set_settings(
      container,
      ContainerSettings.load(node, name) || Settings.default()
    )
  end

  defp hydrate_rows([], _node, _platform, _opts), do: {:ok, []}

  defp hydrate_rows(rows, node, platform, opts)
       when is_list(rows) and is_binary(node) and is_binary(platform) and is_list(opts) do
    with {:ok, context} <- HydrationContext.load(node, platform, opts) do
      rows
      |> Enum.map(&compose(&1, context))
      |> then(&LoadReport.from_results(:container_load, &1))
    end
  end

  defp compose(
         %Database.Container.Record{
           name: name,
           image_id: image_id,
           image_tag: tag,
           image_status: image_status
         } = row,
         %HydrationContext{
           node_data: node_data,
           images_by_id: images_by_id,
           tag_info_by_key: tag_info_by_key,
           settings_by_name: settings_by_name,
           image_digests: image_digests,
           platform: platform
         }
       ) do
    with {:ok, node_data} <- require_node_data(node_data, row.node),
         {:ok, image} <- load_image(images_by_id, image_id, name),
         {:ok, tag_info} <- load_tag_info(tag_info_by_key, tag, platform, name) do
      settings = Map.get(settings_by_name, name, Settings.default())
      image_present = image_present_on_node?(image_status, tag_info, image_digests)
      attributes = persisted_container_attributes(row)

      {:ok,
       RuntimeContainer.from_persisted(
         attributes,
         node_data,
         image,
         tag_info,
         settings,
         image_present
       )}
    else
      {:error, %PersistenceError{} = error} = result ->
        Logger.error("Error loading container [#{name}] from database: #{PersistenceError.format(error)}")
        result
    end
  end

  defp require_node_data(node_data, node) do
    Exdock.Server.State.Storage.Persistence.Result.require_loaded(
      node_data,
      :container_load,
      {:not_found, :node_data, node}
    )
  end

  defp load_image(images_by_id, image_id, container_name) do
    images_by_id
    |> Map.get(image_id)
    |> Exdock.Server.State.Storage.Persistence.Result.require_loaded(
      :container_load,
      {:not_found, :image, %{id: image_id, container: container_name}}
    )
  end

  defp load_tag_info(tag_info_by_key, tag, platform, container_name) do
    tag
    |> Exdock.ImageReference.normalize_tag()
    |> then(&Map.get(tag_info_by_key, {&1, platform}))
    |> Exdock.Server.State.Storage.Persistence.Result.require_loaded(
      :container_load,
      {:not_found, :tag_info, %{tag: tag, platform: platform, container: container_name}}
    )
  end

  defp image_present_on_node?(:updated, %TagInfo{}, _image_digests), do: true

  defp image_present_on_node?(_status, %TagInfo{latest_digest: digest}, image_digests) do
    MapSet.member?(image_digests, digest)
  end

  defp persisted_container_attributes(%Database.Container.Record{} = row) do
    Mapper.runtime_attributes(row)
  end
end
