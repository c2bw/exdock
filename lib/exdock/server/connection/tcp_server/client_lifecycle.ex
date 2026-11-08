defmodule Exdock.Server.Connection.TCPServer.ClientLifecycle do
  @moduledoc """
  Applies connection lifecycle changes to the authoritative runtime owner.
  """

  alias Exdock.Runtime.Coordinator

  @spec reset() :: :ok
  def reset, do: Coordinator.connections_reset()

  @spec ready(String.t(), map()) :: :ok
  def ready(client_name, metadata) when is_binary(client_name) and is_map(metadata),
    do: Coordinator.node_is_up(client_name, metadata)

  @spec disconnected(String.t()) :: :ok
  def disconnected(client_name) when is_binary(client_name),
    do: Coordinator.node_is_down(client_name)
end
