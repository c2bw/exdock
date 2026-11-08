defmodule Exdock.Domain.Container.Core.ImageData do
  @moduledoc """
  Image/tag status embedded in a container core snapshot.
  """

  alias Exdock.Size
  alias Exdock.Domain

  @derive Jason.Encoder
  defstruct [
    :status,
    :tag_info,
    :image,
    :present_on_node
  ]

  @type status :: :unknown | :updated | :outdated | :empty_local_digest | :empty_remote_digest
  @type t :: %__MODULE__{
          status: status(),
          tag_info: Domain.TagInfo.t(),
          image: Domain.Image.t(),
          present_on_node: boolean()
        }

  @spec new(Domain.TagInfo.t(), Domain.Image.t(), boolean()) :: t()
  def new(%Domain.TagInfo{} = tag_info, %Domain.Image{size: size} = image, is_present_on_node) do
    # Store the human-readable size with truncated zero decimals so every
    # container display reads from the same derived image snapshot.
    image = %{image | size_human: Size.human_readable(size, decimals: 0, truncate_zero_decimals: true)}

    %__MODULE__{
      status: image_status(tag_info, Domain.Image.digests_for_tag(image, tag_info.tag)),
      tag_info: tag_info,
      image: image,
      present_on_node: is_present_on_node
    }
  end

  @spec image_status(Domain.TagInfo.t(), [String.t()]) :: status()
  defp image_status(%Domain.TagInfo{check_date: nil}, _local_digest), do: :unknown

  defp image_status(%Domain.TagInfo{latest_digest: remote_digest}, local_digests),
    do: compare_digests(remote_digest, local_digests)

  @spec compare_digests(String.t(), [String.t()]) :: :empty_remote_digest | :empty_local_digest | :updated | :outdated
  defp compare_digests("", _local_digest), do: :empty_remote_digest
  defp compare_digests(_remote_digest, []), do: :empty_local_digest

  defp compare_digests(remote_digest, local_digests),
    do: if(remote_digest in local_digests, do: :updated, else: :outdated)
end
