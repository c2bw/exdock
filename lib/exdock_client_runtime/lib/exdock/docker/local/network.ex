defmodule Exdock.Docker.Local.Network do
  alias Exdock.Docker.Local.{Response, Types}

  @doc """
    Disconnects the container from the network.

    The container_identifier can be the container name or the container id.
  """
  @spec disconnect(Types.connection(), String.t(), DockerEngineAPI.Model.NetworkDisconnectRequest.t()) ::
          Types.result(Types.response())
  def disconnect(conn, network_id, container) do
    DockerEngineAPI.Api.Network.network_disconnect(conn, network_id, container)
    |> Response.expect_status(200)
  end

  @doc """
    Connects the container to the network.

    The container_identifier can be the container name or the container id.
  """
  @spec connect(Types.connection(), String.t(), DockerEngineAPI.Model.NetworkConnectRequest.t()) ::
          Types.result(Types.response())
  def connect(conn, network_id, container) do
    DockerEngineAPI.Api.Network.network_connect(conn, network_id, container)
    |> Response.expect_status(200)
  end
end
