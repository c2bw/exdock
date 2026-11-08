defmodule Exdock.ClientLib.Image do
  @moduledoc """
  Client-side Docker image operations.

  Docker transport stays in this facade while image-reference normalization
  and protocol snapshot mapping live in focused modules.
  """

  require Logger

  alias DockerEngineAPI.Model
  alias Exdock.ClientLib.Image.SnapshotMapper
  alias Exdock.ClientLib.Utils
  alias Exdock.Docker
  alias Exdock.Docker.Error
  alias Exdock.Protocol.Snapshot.Image, as: ImageSnapshot
  alias Exdock.Protocol.ImageReference

  @type t :: ImageSnapshot.t()

  @doc """
  Pull an image from the registry.
  """
  @spec pull(
          Exdock.Docker.Engine.connection(),
          String.t(),
          boolean(),
          atom() | nil,
          String.t() | nil
        ) ::
          {:ok, term() | String.t()} | {:error, Error.t()}
  def pull(conn, reference, stream_response \\ false, job_name \\ nil, job_id \\ nil) do
    tag = ImageReference.ensure_tag(reference)

    if stream_response do
      case Docker.Local.Image.streamed_pull(conn, tag, job_name, job_id) do
        {:ok, tag} -> {:ok, tag}
        {:error, error} -> {:error, Utils.docker_error(:image_pull, error)}
      end
    else
      case Docker.Local.Image.pull(conn, tag) do
        {:ok, response} -> {:ok, response}
        {:error, error} -> {:error, Utils.docker_error(:image_pull, error)}
      end
    end
  end

  @doc """
  Delete an image from the local node.
  """
  @spec delete(Exdock.Docker.Engine.connection(), String.t()) ::
          {:ok, term()} | {:error, Error.t()}
  def delete(conn, image_id) do
    case Docker.Local.Image.delete(conn, image_id) do
      {:ok, response} -> {:ok, response}
      {:error, error} -> {:error, Utils.docker_error(:image_delete, error)}
    end
  end

  @doc """
  Fetch and normalize all images from the local node.
  """
  @spec get_all(Exdock.Docker.Engine.connection()) ::
          {:ok,
           %{
             ok: [ImageSnapshot.t()],
             errored: [{Error.t(), String.t()}]
           }}
          | {:error, Error.t()}
  def get_all(conn) do
    case Docker.Local.Image.list(conn) do
      {:ok, image_summaries} ->
        images =
          image_summaries
          |> Utils.async_stream(&fetch(conn, &1))
          |> Enum.reduce(%{ok: [], errored: []}, fn
            {:ok, {:ok, image}}, acc ->
              Map.update!(acc, :ok, &[image | &1])

            {:ok, {:error, error, image_id}}, acc ->
              Map.update!(acc, :errored, &[{error, image_id} | &1])
          end)

        {:ok, images}

      {:error, error} ->
        {:error, Utils.docker_error(:image_list, error)}
    end
  end

  @spec fetch(Exdock.Docker.Engine.connection(), Model.ImageSummary.t()) ::
          {:ok, ImageSnapshot.t()} | {:error, String.t(), String.t()}
  defp fetch(
         conn,
         %Model.ImageSummary{SharedSize: shared_size, Id: id} = image_summary
       ) do
    source =
      case Docker.Local.Image.inspect(conn, id) do
        {:ok, image_inspect} ->
          image_inspect

        {:error, error} ->
          Logger.error("Image Inspect [#{id}]: #{inspect(error)}")
          image_summary
      end

    case SnapshotMapper.map(source, shared_size) do
      {:ok, image} -> {:ok, image}
      {:error, error} -> {:error, error, id}
    end
  end
end
