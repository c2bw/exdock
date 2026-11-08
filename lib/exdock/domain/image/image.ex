defmodule Exdock.Domain.Image do
  @moduledoc """
  Runtime image projection used by cluster storage and LiveViews.

  The database image row stores durable Docker facts. This struct adds derived
  fields such as human-readable size, repository metadata, registry URL, delete
  settings, and whether a currently known container references the image.
  """
  alias Exdock.Protocol.Snapshot, as: Client
  alias Exdock.ImageReference
  alias Exdock.Size
  alias Exdock.Domain.Image.{Metadata, Settings}

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
    :settings,
    repo_digests: []
  ]

  @type t :: %__MODULE__{
          node: String.t(),
          id: String.t(),
          name: String.t(),
          tags: [String.t()],
          digest: String.t(),
          repo_digests: [String.t()],
          size: integer(),
          shared_size: integer(),
          size_human: String.t(),
          build_date: DateTime.t(),
          # Additional fields, not part of the image struct in the database
          metadata: Metadata.t(),
          # Registry URL can be inferred from the image name
          registry_url: String.t(),
          # In use indicates whether the image is used by any container
          in_use: boolean(),
          settings: Settings.t()
        }

  @type node_id :: Exdock.NodeId.t()

  @spec from_client(Client.Image.t(), node_id(), t() | nil, boolean()) :: t()
  def from_client(%Client.Image{name: name} = image, node, previous, in_use) do
    # Client refreshes provide Docker facts only. Preserve user-maintained
    # metadata/settings from the previous in-memory image when the image remains
    # present across refreshes.
    registry_url = registry_url_for_name(name)
    {metadata, settings} = inherited_runtime_state(previous, name)
    from_client(image, node, metadata, settings, in_use, registry_url)
  end

  @doc """
  Builds an image from client facts and explicitly supplied durable preferences.
  """
  @spec from_client(Client.Image.t(), String.t(), Metadata.t(), Settings.t(), boolean()) :: t()
  def from_client(%Client.Image{name: name} = image, node, %Metadata{} = metadata, %Settings{} = settings, in_use)
      when is_boolean(in_use) do
    from_client(image, node, metadata, settings, in_use, registry_url_for_name(name))
  end

  @doc "Local manifest digests for the container's repository, with legacy snapshot fallback."
  @spec digests_for_tag(t(), String.t()) :: [String.t()]
  def digests_for_tag(%__MODULE__{repo_digests: [], digest: digest}, _tag),
    do: if(is_binary(digest) and digest != "", do: [digest], else: [])

  def digests_for_tag(%__MODULE__{repo_digests: references}, tag) do
    repository = ImageReference.truncate_tag(tag)

    Enum.flat_map(references, fn reference ->
      case String.split(reference, "@", parts: 2) do
        [name, digest] when digest != "" ->
          if ImageReference.truncate_tag(name) == repository, do: [digest], else: []

        _ ->
          []
      end
    end)
  end

  @spec all_digests(t()) :: [String.t()]
  def all_digests(%__MODULE__{repo_digests: [], digest: digest}),
    do: if(is_binary(digest) and digest != "", do: [digest], else: [])

  def all_digests(%__MODULE__{repo_digests: references}) do
    Enum.flat_map(references, fn reference ->
      case String.split(reference, "@", parts: 2) do
        [_name, digest] when digest != "" -> [digest]
        _ -> []
      end
    end)
  end

  @spec update(t(), [String.t()]) :: t()
  def update(%__MODULE__{} = image, images_id) do
    # Container storage can change independently of image facts, so image
    # projections refresh their in-use flag from the latest container image ids.
    image
    |> set_in_use(images_id)
  end

  @spec locked?(t()) :: boolean()
  def locked?(%__MODULE__{settings: %{delete_lock: locked}} = _image), do: locked
  @spec in_use?(t()) :: boolean()
  def in_use?(%__MODULE__{in_use: in_use} = _image), do: in_use

  @spec from_client(
          Client.Image.t(),
          node_id(),
          Metadata.t(),
          Settings.t(),
          boolean(),
          String.t()
        ) :: t()
  defp from_client(
         %Client.Image{
           id: id,
           name: name,
           tags: tags,
           digest: digest,
           repo_digests: repo_digests,
           size: size,
           shared_size: s_size,
           build_date: date
         },
         node,
         %Metadata{} = metadata,
         %Settings{} = settings,
         in_use,
         registry_url
       )
       when is_binary(node) and is_binary(registry_url) and is_boolean(in_use) do
    from_persisted(%{
      node: node,
      id: id,
      name: name,
      tags: tags,
      digest: digest,
      repo_digests: repo_digests,
      size: size,
      shared_size: s_size,
      build_date: date,
      metadata: metadata,
      registry_url: registry_url,
      in_use: in_use,
      settings: settings
    })
  end

  @spec set_registry_url(t(), String.t()) :: t()
  def set_registry_url(%__MODULE__{} = image, url) when is_binary(url), do: %{image | registry_url: url}
  @spec set_metadata(t(), Metadata.t()) :: t()
  def set_metadata(%__MODULE__{} = image, %Metadata{} = metadata), do: %{image | metadata: metadata}

  @spec set_in_use(t(), [String.t()] | boolean()) :: t()
  def set_in_use(%__MODULE__{id: id} = image, ids) when is_list(ids), do: set_in_use(image, image_is_in_use?(id, ids))
  def set_in_use(%__MODULE__{} = image, in_use) when is_boolean(in_use), do: %{image | in_use: in_use}
  @spec set_settings(t(), Settings.t()) :: t()
  def set_settings(%__MODULE__{} = image, %Settings{} = settings), do: %{image | settings: settings}

  @spec image_is_in_use?(String.t(), [String.t()]) :: boolean()
  defp image_is_in_use?(id, ids) when is_binary(id) and is_list(ids), do: Enum.any?(ids, fn i -> i == id end)

  defp inherited_runtime_state(nil, name), do: {metadata_for_name(name), Settings.default()}
  defp inherited_runtime_state(%__MODULE__{metadata: metadata, settings: settings}, _name), do: {metadata, settings}

  defp metadata_for_name(name) when is_binary(name), do: Metadata.default(name)

  @spec get_repository(t()) :: String.t()
  def get_repository(%__MODULE__{metadata: %Metadata{repository_url: url}} = _image) when is_binary(url), do: url

  @spec registry_url_for_name(String.t()) :: String.t()
  defp registry_url_for_name(name) when is_binary(name), do: ImageReference.registry_url(name)

  @doc """
  Builds a runtime image from persistence-neutral attributes.
  """
  @spec from_persisted(map()) :: t()
  def from_persisted(attrs) when is_map(attrs) do
    # Database loads and client refreshes arrive with different source structs,
    # but both are normalized into this app-level image projection.
    %__MODULE__{
      node: Map.fetch!(attrs, :node),
      id: Map.fetch!(attrs, :id),
      name: Map.fetch!(attrs, :name),
      tags: Map.fetch!(attrs, :tags),
      digest: Map.fetch!(attrs, :digest),
      repo_digests: Map.get(attrs, :repo_digests, []),
      size: Map.fetch!(attrs, :size),
      shared_size: Map.fetch!(attrs, :shared_size),
      size_human: attrs |> Map.fetch!(:size) |> Size.human_readable(),
      build_date: Map.fetch!(attrs, :build_date),
      metadata: Map.fetch!(attrs, :metadata),
      registry_url: Map.fetch!(attrs, :registry_url),
      in_use: Map.fetch!(attrs, :in_use),
      settings: Map.fetch!(attrs, :settings)
    }
  end
end
