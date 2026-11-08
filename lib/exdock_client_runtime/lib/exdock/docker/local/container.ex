defmodule Exdock.Docker.Local.Container do
  @moduledoc """
  Thin normalization layer over Docker Engine container APIs.

  The generated Docker client returns a mix of model structs, Tesla responses,
  and error structs. This module keeps the rest of Exdock on a consistent
  `{:ok, value}` / `{:error, reason}` contract and documents which HTTP statuses
  are considered successful for each container operation.
  """

  alias DockerEngineAPI.Model
  alias Exdock.Docker.Local.{Response, Types}

  @doc """
    Returns a list of container summaries.

    # Parameters
    - `conn` - The connection to the Docker Engine.
    - `include_stopped` - Whether to include stopped containers in the list. Defaults to `true`.
  """
  @spec list(Types.connection(), boolean()) :: Types.result(any())
  def list(conn, include_stopped \\ true) do
    DockerEngineAPI.Api.Container.container_list(conn, all: include_stopped)
    |> Response.reject_struct(Model.ErrorResponse)
  end

  @doc """
    Returns the full container inspect information for the given container_identifier.

    The container_identifier can be the container name or the container id.
  """
  @spec inspect(Types.connection(), String.t()) :: Types.result(Model.ContainerInspectResponse.t())
  def inspect(conn, container_id) do
    DockerEngineAPI.Api.Container.container_inspect(conn, container_id)
    |> Response.expect_struct(Model.ContainerInspectResponse)
  end

  @doc """
    Starts the container.

    The container_identifier can be the container name or the container id.
  """
  @spec start(Types.connection(), String.t()) :: Types.result(Types.response())
  def start(conn, container_id) do
    DockerEngineAPI.Api.Container.container_start(conn, container_id)
    # Docker reports "already started" as 304; the UI treats that as a
    # successful idempotent start request.
    |> Response.expect_status([204, 304])
  end

  @doc """
    Stops the container.

    The container_identifier can be the container name or the container id.
  """
  @spec stop(Types.connection(), String.t()) :: Types.result(Types.response())
  def stop(conn, container_id) do
    DockerEngineAPI.Api.Container.container_stop(conn, container_id)
    # Docker reports "already stopped" as 304; Exdock can safely surface the
    # final desired state as successful.
    |> Response.expect_status([204, 304])
  end

  @doc "Restarts through Docker's native API, preserving auto-remove containers."
  @spec restart(Types.connection(), String.t()) :: Types.result(Types.response())
  def restart(conn, container_id) do
    DockerEngineAPI.Api.Container.container_restart(conn, container_id)
    |> Response.expect_status(204)
  end

  @doc """
    Deletes the container.

    The container_identifier can be the container name or the container id.
  """
  @spec delete(Types.connection(), String.t()) :: Types.result(Types.response())
  def delete(conn, container_id) do
    DockerEngineAPI.Api.Container.container_delete(conn, container_id)
    |> Response.expect_status(204)
  end

  @doc """
    Renames the container.

    The container_identifier can be the container name or the container id.
  """
  @spec rename(Types.connection(), String.t(), String.t()) :: Types.result(Types.response())
  def rename(conn, container_id, new_name) do
    DockerEngineAPI.Api.Container.container_rename(conn, container_id, new_name)
    |> Response.expect_status(204)
  end

  @doc """
    Creates a container using the given container_configuration.

    # Parameters
    - `conn` - The connection to the Docker Engine.
    - `container_name` - The name of the container.
    - `container_configuration` - The container configuration.
  """
  @spec create(Types.connection(), String.t(), Model.ContainerCreateRequest.t()) ::
          Types.result(Model.ContainerCreateResponse.t())
  def create(conn, container_name, container_configuration) do
    DockerEngineAPI.Api.Container.container_create(
      conn,
      container_configuration,
      name: container_name
    )
    |> Response.expect_struct(Model.ContainerCreateResponse)
  end

  @doc """
    Returns the logs of the container.

    The container_identifier can be the container name or the container id.
  """
  @spec log(Types.connection(), String.t(), Keyword.t()) :: Types.result(Types.response())
  def log(conn, container_id, opts \\ []) do
    DockerEngineAPI.Api.Container.container_logs(conn, container_id, opts)
    |> Response.expect_status(200)
  end

  @doc """
    Returns the resource usage of the container.

    The container_identifier can be the container name or the container id.

    Note: This is a slow request (1000ms)
  """
  @spec resource_usage(Types.connection(), String.t()) ::
          Types.result(DockerEngineAPI.Model.ContainerStatsResponse.t())
  def resource_usage(conn, container_id) do
    DockerEngineAPI.Api.Container.container_stats(conn, container_id, stream: false)
    |> Response.reject_struct(Model.ErrorResponse)
  end
end
