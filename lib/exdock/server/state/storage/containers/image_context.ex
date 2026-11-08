defmodule Exdock.Server.State.Storage.Containers.ImageContext do
  @moduledoc false

  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Domain

  defstruct [:by_id, :digests, :platform]

  @type t :: %__MODULE__{
          by_id: %{String.t() => Domain.Image.t()},
          digests: MapSet.t(String.t()),
          platform: String.t()
        }

  @spec new(NodeStorage.t(), String.t()) :: t()
  def new(%NodeStorage{} = storage, node) when is_binary(node) do
    images = Storage.Images.list_node(storage, node)

    %__MODULE__{
      by_id: Map.new(images, &{&1.id, &1}),
      digests: images |> Enum.flat_map(&Domain.Image.all_digests/1) |> MapSet.new(),
      platform: node_platform!(storage, node)
    }
  end

  @spec image(t(), String.t()) :: Domain.Image.t() | nil
  def image(%__MODULE__{by_id: images}, image_id) when is_binary(image_id),
    do: Map.get(images, image_id)

  @spec tag_info(t(), Storage.TagsInfo.t(), String.t()) :: Domain.TagInfo.t()
  def tag_info(
        %__MODULE__{platform: platform},
        %Storage.TagsInfo{} = tags,
        tag
      )
      when is_binary(tag) do
    normalized_tag = Exdock.ImageReference.normalize_tag(tag)

    Storage.TagsInfo.get(tags, normalized_tag, platform) ||
      Domain.TagInfo.default(normalized_tag, platform)
  end

  @spec digest_present?(t(), Domain.TagInfo.t()) :: boolean()
  def digest_present?(
        %__MODULE__{digests: digests},
        %Domain.TagInfo{latest_digest: digest}
      ) do
    MapSet.member?(digests, digest)
  end

  defp node_platform!(%NodeStorage{} = storage, node) do
    case Storage.Nodes.get(storage, node) do
      %Domain.Node{metadata: %{"platform" => platform}}
      when is_binary(platform) and platform != "" ->
        platform

      _missing ->
        raise ArgumentError, "missing container platform for node #{inspect(node)}"
    end
  end
end
