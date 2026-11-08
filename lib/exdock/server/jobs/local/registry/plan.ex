defmodule Exdock.Server.Jobs.Local.Registry.Plan do
  @moduledoc """
  Pure request planning for registry refresh jobs.

  It derives node platforms and de-duplicates the tag/platform pairs used by
  running containers without performing remote work or publishing job effects.
  """

  alias Exdock.Server.State.Storage
  alias Exdock.Domain

  @spec node_platforms(Storage.Cluster.Utils.NodeStorage.t()) ::
          %{String.t() => String.t() | nil}
  def node_platforms(storage) do
    storage
    |> Storage.Nodes.string_map()
    |> Map.new(fn {node, %Domain.Node{metadata: metadata}} ->
      {node, Map.get(metadata, "platform")}
    end)
  end

  @spec running_image_requests(
          [Exdock.Domain.Container.t()],
          %{String.t() => String.t()}
        ) :: [%{tag: String.t(), platform: String.t()}]
  def running_image_requests(containers, platforms_by_node)
      when is_list(containers) and is_map(platforms_by_node) do
    {requests, _seen} =
      Enum.reduce(containers, {[], MapSet.new()}, fn
        %{node: node, core: %{is_running: true}} = container, {requests, seen} ->
          image_tag = Domain.Container.image_tag(container)
          platform = platform_for_node!(platforms_by_node, node)
          image_tag = Exdock.ImageReference.normalize_tag(image_tag)
          request = %{tag: image_tag, platform: platform}
          key = {image_tag, platform}

          if Exdock.ImageReference.image_id?(image_tag) or MapSet.member?(seen, key) do
            {requests, seen}
          else
            {[request | requests], MapSet.put(seen, key)}
          end

        _container, accumulator ->
          accumulator
      end)

    Enum.reverse(requests)
  end

  defp platform_for_node!(platforms_by_node, node) do
    case Map.fetch(platforms_by_node, node) do
      {:ok, platform} when is_binary(platform) and platform != "" ->
        platform

      _missing ->
        raise ArgumentError, "missing registry platform for node #{inspect(node)}"
    end
  end
end
