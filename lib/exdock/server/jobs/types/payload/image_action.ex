defmodule Exdock.Server.Jobs.Payload.ImageAction do
  @moduledoc "Metadata for image pull and delete jobs."

  defstruct [:node, :image_tag, :image_id, image_tags: []]

  @type t :: %__MODULE__{
          node: String.t(),
          image_tag: String.t() | nil,
          image_id: String.t() | nil,
          image_tags: [String.t()]
        }

  @spec pull(String.t(), String.t()) :: t()
  def pull(node, image_tag) when is_binary(node) and is_binary(image_tag),
    do: %__MODULE__{node: node, image_tag: image_tag}

  @spec delete(String.t(), String.t(), [String.t()]) :: t()
  def delete(node, image_id, image_tags)
      when is_binary(node) and is_binary(image_id) and is_list(image_tags),
      do: %__MODULE__{node: node, image_id: image_id, image_tags: image_tags}
end
