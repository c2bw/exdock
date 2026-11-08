defmodule Exdock.Server.Connection.TCPServer.HandshakeWorker.Port.SSL do
  @moduledoc "Production handshake port backed by Erlang SSL and the connection handler."

  @behaviour Exdock.Server.Connection.TCPServer.HandshakeWorker.Port

  alias Exdock.Server.Connection
  alias Exdock.Server.Connection.TCPServer.HandlerSupervisor

  @impl true
  def close(_context, socket), do: :ssl.close(socket)

  @impl true
  def controlling_process(_context, socket, pid), do: :ssl.controlling_process(socket, pid)

  @impl true
  def handshake(_context, socket, timeout), do: :ssl.handshake(socket, timeout)

  @impl true
  def setopts(_context, socket, opts), do: :ssl.setopts(socket, opts)

  @impl true
  def start_handler(_context, server, auth_key, socket, handler_supervisor),
    do: HandlerSupervisor.start_handler(server, auth_key, socket, handler_supervisor)

  @impl true
  def stop_handler(_context, handler_pid, reason),
    do: Connection.Handler.stop(handler_pid, reason)

  @impl true
  def activate_handler(_context, handler_pid),
    do: Connection.Handler.activate_socket(handler_pid)
end
