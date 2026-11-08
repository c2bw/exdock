defmodule Exdock.Docker.Local.Image do
  @moduledoc """
  Thin normalization layer over Docker Engine image APIs.

  Callers use this module instead of the generated Docker API directly so image
  inspection, listing, pulling, deletion, and streamed pulls expose predictable
  success/error tuples.
  """

  alias DockerEngineAPI.Model
  alias Exdock.Docker.Local.ImagePull
  alias Exdock.Docker.Local.{Response, Types}

  @doc """
    Returns the full image inspect information for the given image_identifier.

    The image_identifier can be the image name or the image id.
  """
  @spec inspect(Types.connection(), String.t()) :: Types.result(Model.ImageInspect.t())
  def inspect(conn, image_id) do
    DockerEngineAPI.Api.Image.image_inspect(conn, image_id)
    |> Response.expect_struct(Model.ImageInspect)
  end

  @doc """
    Returns a list of all the images stored on the local node.

    By default, only the final layer of each image is returned. If you want to get all the layers of each image, set `only_final_layer` to `false`.
  """
  @spec list(Types.connection(), boolean()) :: Types.result(any())
  def list(conn, only_final_layer \\ true) do
    DockerEngineAPI.Api.Image.image_list(conn, all: not only_final_layer)
    # Image list can also return an ErrorResponse in the success channel;
    # callers only receive `{:ok, list}` when the payload is usable.
    |> Response.reject_struct(Model.ErrorResponse)
  end

  @doc """
      Pulls the image from the registry.
  """
  @spec pull(Types.connection(), String.t()) :: Types.result(Types.response())
  def pull(conn, image_tag) do
    DockerEngineAPI.Api.Image.image_create(conn, fromImage: image_tag)
    # The generated client returns the raw streaming response; a 200 means
    # Docker accepted the pull stream.
    |> Response.expect_status(200)
  end

  @doc """
    Deletes the image from the local node.

    The image_id can be the image name or the image id.
  """
  @spec delete(Types.connection(), String.t()) :: Types.result(any())
  def delete(conn, image_id) do
    DockerEngineAPI.Api.Image.image_delete(conn, image_id)
    |> Response.reject_struct(Model.ErrorResponse)
  end

  @spec streamed_pull(Types.connection(), String.t(), atom() | nil, String.t() | nil) ::
          {:ok, String.t()} | {:error, Exdock.Docker.Error.t()}
  def streamed_pull(conn, image_tag, job_name, job_id),
    do: ImagePull.run(conn, image_tag, job_name, job_id)
end
