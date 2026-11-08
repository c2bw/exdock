defmodule Exdock.ClientLib.Container.Resources do
  @moduledoc """
  Retrieves container statistics and schedules asynchronous resource samples.
  """

  alias Exdock.ClientLib, as: Client
  alias Exdock.ClientLib.Async
  alias Exdock.ClientLib.Utils
  alias Exdock.Docker
  alias Exdock.Docker.Error
  alias Exdock.Protocol.Snapshot.Container, as: ContainerSnapshot

  @spec get_resources(Exdock.Docker.Engine.connection(), String.t()) ::
          {:ok, DockerEngineAPI.Model.ContainerStatsResponse.t()} | {:error, Error.t()}
  def get_resources(conn, container_id) do
    case Docker.Local.Container.resource_usage(conn, container_id) do
      {:ok, response} -> {:ok, response}
      {:error, error} -> {:error, Utils.docker_error(:container_resources, error)}
    end
  end

  @spec maybe_schedule(Exdock.Docker.Engine.connection(), ContainerSnapshot.t(), boolean()) :: :ok
  def maybe_schedule(conn, %ContainerSnapshot{id: id, is_running: true}, true) do
    request = fn -> get_resources(conn, id) end

    Async.Batch.new(:container_resources, id, 3, 3000, request)
    |> Client.add_async_batch()
  end

  def maybe_schedule(_conn, %ContainerSnapshot{}, _retrieve_resources), do: :ok
end
