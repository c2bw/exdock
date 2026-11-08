defmodule Exdock.Server.State.Storage.Containers.SnapshotBuilder do
  @moduledoc false

  alias Exdock.Protocol.Snapshot, as: Client
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Server.State.Storage.Containers.ImageContext
  alias Exdock.Domain.Container

  @spec make(
          NodeStorage.t(),
          String.t(),
          [Client.Container.t()],
          Storage.TagsInfo.t()
        ) :: NodeStorage.t()
  def make(
        %NodeStorage{} = storage,
        node,
        containers,
        %Storage.TagsInfo{} = tags
      )
      when is_binary(node) and is_list(containers) do
    %Exdock.Domain.Node{fetched_at: fetched_at} = Storage.Nodes.get(storage, node)

    previous_by_name =
      storage
      |> NodeStorage.get_containers(node)
      |> Map.new(&{&1.name, &1})

    context = ImageContext.new(storage, node)

    refreshed =
      build_containers(
        node,
        containers,
        previous_by_name,
        context,
        tags,
        fetched_at
      )

    NodeStorage.put_containers(storage, node, refreshed)
  end

  defp build_containers(
         node,
         containers,
         previous_by_name,
         %ImageContext{} = context,
         %Storage.TagsInfo{} = tags,
         fetched_at
       ) do
    Enum.flat_map(containers, fn %Client.Container{image_id: image_id} = snapshot ->
      case ImageContext.image(context, image_id) do
        nil ->
          []

        image ->
          previous = Map.get(previous_by_name, snapshot.name)
          tag_info = ImageContext.tag_info(context, tags, snapshot.image_tag)
          image_present? = ImageContext.digest_present?(context, tag_info)

          [
            Container.from_client(
              node,
              snapshot,
              previous,
              image,
              tag_info,
              image_present?,
              fetched_at
            )
          ]
      end
    end)
  end
end
