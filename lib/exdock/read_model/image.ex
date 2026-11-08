defmodule Exdock.ReadModel.Image do
  @moduledoc "Public image projection consumed by delivery layers."

  alias Exdock.{ImageReference, ReadModel.Value}

  defstruct [
    :node,
    :id,
    :name,
    :tags,
    :digest,
    :size,
    :shared_size,
    :size_human,
    :build_date,
    :metadata,
    :registry_url,
    :in_use,
    :settings
  ]

  @fields [
    :node,
    :id,
    :name,
    :tags,
    :digest,
    :size,
    :shared_size,
    :size_human,
    :build_date,
    :metadata,
    :registry_url,
    :in_use,
    :settings
  ]

  @type t :: %__MODULE__{
          node: String.t(),
          id: String.t(),
          name: String.t(),
          tags: [String.t()],
          digest: String.t(),
          size: integer(),
          shared_size: integer(),
          size_human: String.t(),
          build_date: DateTime.t(),
          metadata: map(),
          registry_url: String.t(),
          in_use: boolean(),
          settings: map()
        }

  def from_domain(%__MODULE__{} = image), do: image

  @spec from_domain(map()) :: t()
  def from_domain(image) when is_map(image) do
    struct!(__MODULE__, image |> Map.take(@fields) |> Value.project())
  end

  @doc "Flattens a node-keyed image projection for cluster-level summaries."
  @spec flatten_node_map(%{String.t() => [t()]}) :: [t()]
  def flatten_node_map(images) when is_map(images) do
    images
    |> Map.values()
    |> List.flatten()
  end

  @spec normalize_tag(String.t()) :: String.t()
  def normalize_tag(tag), do: ImageReference.normalize_tag(tag)

  @spec categorize_registry(String.t()) :: String.t()
  def categorize_registry(image_name), do: ImageReference.categorize_registry(image_name)
end
