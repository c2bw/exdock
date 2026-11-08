defmodule Exdock.Server.State.Storage.Containers.ConfigurationReloader do
  @moduledoc false

  require Logger

  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage.Containers.ImageContext
  alias Exdock.Server.State.Storage.Persistence.Container, as: ContainerPersistence
  alias Exdock.Domain.Container

  @spec reload(NodeStorage.t(), Storage.TagsInfo.t(), boolean()) ::
          NodeStorage.t()
  def reload(
        %NodeStorage{} = storage,
        %Storage.TagsInfo{} = tags,
        reload_settings?
      )
      when is_boolean(reload_settings?) do
    storage
    |> NodeStorage.containers_map()
    |> Enum.reduce(storage, fn {node, containers}, acc ->
      context = ImageContext.new(storage, node)
      refreshed = reload_node(containers, context, tags, reload_settings?)
      NodeStorage.put_containers(acc, node, refreshed)
    end)
  end

  defp reload_node(containers, %ImageContext{} = context, %Storage.TagsInfo{} = tags, reload_settings?) do
    Enum.flat_map(
      containers,
      &reload_container(&1, context, tags, reload_settings?)
    )
  end

  defp reload_container(
         %Container{} = container,
         %ImageContext{} = context,
         %Storage.TagsInfo{} = tags,
         reload_settings?
       ) do
    image = ImageContext.image(context, Container.image_id(container))

    case image do
      nil ->
        Logger.error("Skipping container reload because image is missing: node=#{container.node} name=#{container.name}")

        []

      image ->
        tag_info = ImageContext.tag_info(context, tags, Container.image_tag(container))
        image_present? = ImageContext.digest_present?(context, tag_info)

        refreshed =
          container
          |> Container.update(image, tag_info, image_present?)
          |> maybe_reload_settings(reload_settings?)

        [refreshed]
    end
  end

  defp maybe_reload_settings(%Container{} = container, true),
    do: ContainerPersistence.reload_settings(container)

  defp maybe_reload_settings(%Container{} = container, false), do: container
end
