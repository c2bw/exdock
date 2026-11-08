defmodule Exdock.ClientLib.Image.SnapshotMapper do
  @moduledoc """
  Maps Docker image summary or inspect responses to protocol snapshots.

  The mapper accepts both response shapes because Docker inspect can fail after
  a successful list operation. In that case the list summary remains a valid
  fallback source.
  """

  require Logger

  alias DockerEngineAPI.Model
  alias Exdock.Protocol.ImageReference
  alias Exdock.Protocol.Snapshot.Image, as: ImageSnapshot

  @type source :: Model.ImageInspect.t() | Model.ImageSummary.t()

  @spec map(source(), integer()) :: {:ok, ImageSnapshot.t()} | {:error, String.t()}
  def map(source, shared_size)

  def map(
        %Model.ImageInspect{
          RepoDigests: digests,
          RepoTags: tags,
          Id: id,
          Size: size,
          Created: created
        },
        shared_size
      ) do
    build(digests || [], tags || [], id, size, shared_size, created)
  end

  def map(
        %Model.ImageSummary{
          RepoDigests: digests,
          RepoTags: tags,
          Id: id,
          Size: size,
          Created: created
        },
        shared_size
      ) do
    build(digests || [], tags || [], id, size, shared_size, created)
  end

  defp build(digests, tags, id, size, shared_size, created)
       when is_list(digests) and is_list(tags) do
    digests = normalize_references(digests)
    tags = normalize_references(tags)

    with {:ok, name} <- image_name(digests, tags, id),
         {:ok, build_date} <- build_date(created) do
      digest = digest(digests, name, id)
      tags = if tags == [] and name != id, do: ["#{name}:<none>"], else: tags

      {:ok,
       %ImageSnapshot{
         id: id,
         name: name,
         tags: tags,
         digest: digest,
         repo_digests: digests,
         size: size,
         shared_size: shared_size,
         build_date: build_date
       }}
    else
      {:error, reason} ->
        Logger.error("Failed to transform Image Inspect: #{reason}")
        {:error, reason}
    end
  end

  # Docker's missing-reference placeholders carry no repository identity.
  # Removing them lets dangling images use their immutable image ID instead.
  defp normalize_references(references) do
    Enum.reject(references, fn
      nil -> true
      reference when is_binary(reference) -> String.trim(reference) in ["", "<none>", "<none>:<none>", "<none>@<none>"]
      _reference -> false
    end)
  end

  defp image_name([], [], id) when is_binary(id) and id != "", do: {:ok, id}
  defp image_name(digests, tags, _id), do: image_name(digests, tags)

  defp image_name([digest | _rest], tags) do
    case ImageReference.repository(digest) do
      "" -> image_name([], tags)
      name -> {:ok, name}
    end
  end

  defp image_name([], [tag | _rest]) do
    case ImageReference.repository(tag) do
      "" -> {:error, "image has empty digest and tags"}
      name -> {:ok, name}
    end
  end

  defp image_name([], []), do: {:error, "image has empty digest and tags"}

  defp digest([value | _rest], _name, _id) do
    case String.split(value, "@", parts: 2) do
      [_repository, digest] when digest != "" -> digest
      _parts -> ""
    end
  end

  defp digest([], id, id), do: ""

  defp digest([], name, id) do
    Logger.warning("Image [#{name}, #{id}]: unable to retrieve digest (registry v1 image?)")

    ""
  end

  defp build_date(created) when is_integer(created) do
    case DateTime.from_unix(created) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, reason} -> invalid_date(reason)
    end
  end

  defp build_date(created) when is_binary(created) do
    case DateTime.from_iso8601(created) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> invalid_date(reason)
    end
  end

  defp build_date(created), do: invalid_date({:invalid_created_at, created})

  defp invalid_date(reason) do
    Logger.warning("Unable to parse image creation date: #{inspect(reason)}")
    {:ok, DateTime.from_unix!(0)}
  end
end
