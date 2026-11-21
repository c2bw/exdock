defmodule Exdock.Server.Connection.Native.Registry do
  @moduledoc "Compatibility lookup surface backed only by NodeWire's authoritative registry."
  use GenServer

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Exdock.Server.Connection.TCPServer.ClientRegistry)

  def init(opts), do: {:ok, Keyword.fetch!(opts, :server)}

  def handle_call({:fetch, identity}, _, server) do
    reply =
      case NodeWire.Server.connection(server, identity) do
        {:ok, conn} -> {:ok, conn.owner}
        :error -> :error
      end

    {:reply, reply, server}
  end

  def handle_call(:connected_clients, _, server),
    do: {:reply, Map.new(NodeWire.Server.connections(server), &{&1.identity, &1.owner}), server}
end
