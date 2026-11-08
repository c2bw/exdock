defmodule Exdock.Domain.Image.Metadata do
  @moduledoc """
   Handle metadata for images.

   An image_identifier can be either a tag or its name (e.g. `my_image:latest` or `my_image`).
  """

  alias Exdock.{ImageReference, URL}
  alias Exdock.Domain.ImportFields

  @import_fields [
    {"repository_url", :repository_url, &__MODULE__.valid_repository_url?/1}
  ]

  defstruct [
    :repository_url
  ]

  @type t :: %__MODULE__{
          repository_url: String.t()
        }

  @spec default(String.t()) :: t()
  def default(image_identifier) when is_binary(image_identifier) do
    image_identifier
    |> ImageReference.repository_url()
    |> new()
  end

  @spec set_repository_url(t(), String.t()) :: t()
  def set_repository_url(%__MODULE__{} = metadata, url), do: set(metadata, :repository_url, url)

  @spec set(t(), atom(), any()) :: t()
  defp set(%__MODULE__{} = metadata, :repository_url, url) when is_binary(url),
    do: %{metadata | repository_url: URL.normalize_external(url)}

  @doc """
  Build image metadata from imported data.

  Invalid fields retain their defaults.
  """
  @spec from_import(map(), binary()) :: t()
  def from_import(%{} = unsafe, image_identifier)
      when is_binary(image_identifier) and image_identifier != "" do
    default(image_identifier)
    |> ImportFields.apply_fields(unsafe, @import_fields, &set/3)
  end

  @doc false
  def valid_repository_url?(value), do: is_binary(value) and value != ""

  @spec new(String.t()) :: t()
  def new(repository_url) when is_binary(repository_url), do: %__MODULE__{repository_url: repository_url}

  # Metadata is stored under the tag-normalized image name so custom repository
  # links survive mutable tag/version refreshes like `app:1.2.3` -> `app:latest`.
  @doc false
  def metadata_name(image_identifier), do: ImageReference.truncate_tag(image_identifier)
end
