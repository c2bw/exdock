defmodule Exdock.Server.State.Storage.Persistence.Container.HydrationContext do
  @moduledoc """
  Preloaded persistence data shared while hydrating a container batch.

  Keeping this boundary explicit documents the data required by container
  composition and guarantees each supporting table is loaded only once.
  """

  alias Exdock.Domain.{Image, Node, TagInfo}
  alias Exdock.Domain.Container.Settings
  alias Exdock.Server.State.Storage.Persistence.ContainerSettings
  alias Exdock.Server.State.Storage.Persistence.Image, as: ImagePersistence
  alias Exdock.Server.State.Storage.Persistence.LoadReport
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Server.State.Storage.Persistence.TagInfo, as: TagInfoPersistence

  @enforce_keys [
    :node_data,
    :images_by_id,
    :tag_info_by_key,
    :settings_by_name,
    :image_digests,
    :platform
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          node_data: Node.t() | nil,
          images_by_id: %{optional(String.t()) => Image.t()},
          tag_info_by_key: %{optional({String.t(), String.t()}) => TagInfo.t()},
          settings_by_name: %{optional(String.t()) => Settings.t()},
          image_digests: MapSet.t(String.t()),
          platform: String.t()
        }

  @spec load(Exdock.NodeId.t(), String.t(), keyword()) ::
          {:ok, t()} | {:error, LoadReport.t(term())}
  def load(node, platform, opts)
      when is_binary(node) and is_binary(platform) and is_list(opts) do
    node_data = Keyword.get_lazy(opts, :node_data, fn -> NodePersistence.load(node) end)

    with {:ok, images} <- load_images(node, opts) do
      {:ok,
       %__MODULE__{
         node_data: node_data,
         images_by_id: Map.new(images, &{&1.id, &1}),
         tag_info_by_key: tag_info_by_key(TagInfoPersistence.load_all()),
         settings_by_name: ContainerSettings.load_node(node),
         image_digests: MapSet.new(images, & &1.digest),
         platform: platform
       }}
    end
  end

  defp load_images(node, opts) do
    case Keyword.fetch(opts, :images) do
      {:ok, images} when is_list(images) -> {:ok, images}
      {:ok, images} -> {:error, LoadReport.new(:container_load, {:invalid_images, images})}
      :error -> ImagePersistence.load_node(node)
    end
  end

  defp tag_info_by_key(tag_infos) do
    Map.new(tag_infos, fn %TagInfo{tag: tag, platform: platform} = tag_info ->
      {{tag, platform}, tag_info}
    end)
  end
end
