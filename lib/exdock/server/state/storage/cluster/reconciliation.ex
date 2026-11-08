defmodule Exdock.Server.State.Storage.Cluster.Reconciliation do
  @moduledoc """
  Builds the latest in-memory cluster projection from a client snapshot.

  Reconciliation deliberately does not write cluster rows or deletion markers.
  The persistence layer compares the previous and reconciled projections and
  owns all durable effects.
  """

  alias Exdock.Protocol.Snapshot, as: Client
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage

  @spec reconcile(
          map(),
          String.t(),
          [Client.Container.t()],
          [Client.Image.t()],
          Storage.TagsInfo.t(),
          DateTime.t()
        ) :: map()
  @spec reconcile(map(), String.t(), [Client.Container.t()], [Client.Image.t()], Storage.TagsInfo.t(), DateTime.t(), keyword()) ::
          map()
  def reconcile(
        %{storage: %NodeStorage{} = storage} = cluster,
        node,
        containers,
        images,
        %Storage.TagsInfo{} = tags_info,
        %DateTime{} = fetched_at,
        opts \\ []
      )
      when is_binary(node) and is_list(containers) and is_list(images) do
    failed_names = MapSet.new(Keyword.get(opts, :preserve_containers, []))
    failed_images = MapSet.new(Keyword.get(opts, :preserve_images, []))
    previous_containers = Storage.Containers.list_node(storage, node)
    previous_images = Storage.Images.list_node(storage, node)

    # If a new image cannot be inspected, keep a known container by name rather
    # than dropping it when its current image cannot yet be joined.
    failed_names =
      Enum.reduce(containers, failed_names, fn container, names ->
        if MapSet.member?(failed_images, container.image_id), do: MapSet.put(names, container.name), else: names
      end)

    retained_containers = Enum.filter(previous_containers, &MapSet.member?(failed_names, &1.name))
    used_ids = container_image_ids(containers) ++ Enum.map(retained_containers, &Exdock.Domain.Container.image_id/1)

    retained_image_ids =
      MapSet.union(failed_images, MapSet.new(Enum.map(retained_containers, &Exdock.Domain.Container.image_id/1)))

    refreshed =
      storage
      |> Storage.Nodes.make(node, fetched_at)
      |> Storage.Images.make(node, images, used_ids)

    retained_images =
      previous_images
      |> Enum.filter(&MapSet.member?(retained_image_ids, &1.id))
      |> Enum.map(&Exdock.Domain.Image.update(&1, used_ids))

    merged_images = merge_retained(Storage.Images.list_node(refreshed, node), retained_images, & &1.id)
    refreshed = refreshed |> Storage.Images.set_node(node, merged_images) |> Storage.Containers.make(node, containers, tags_info)
    merged_containers = merge_retained(Storage.Containers.list_node(refreshed, node), retained_containers, & &1.name)

    %{cluster | storage: Storage.Containers.set_node(refreshed, node, merged_containers)}
  end

  defp merge_retained(current, retained, key) do
    current_ids = MapSet.new(current, key)
    current ++ Enum.reject(retained, &MapSet.member?(current_ids, key.(&1)))
  end

  @spec container_image_ids([Client.Container.t()]) :: [String.t()]
  defp container_image_ids(containers) do
    Enum.map(containers, fn %Client.Container{image_id: id} -> id end)
  end
end
