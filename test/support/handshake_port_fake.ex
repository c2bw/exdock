defmodule Exdock.Server.Connection.HandshakePortFake do
  @moduledoc false

  @behaviour Exdock.Server.Connection.TCPServer.HandshakeWorker.Port

  @impl true
  def close(%{owner: owner}, socket) do
    send(owner, {:closed, socket})
    :ok
  end

  @impl true
  def controlling_process(%{scenario: :handoff_failure}, :accepted_socket, worker)
      when is_pid(worker),
      do: {:error, :not_owner}

  def controlling_process(_context, _socket, _pid), do: :ok

  @impl true
  def handshake(%{scenario: :handshake_failure}, :accepted_socket, 25),
    do: {:error, :bad_certificate}

  def handshake(_context, :accepted_socket, _timeout), do: {:ok, :client_socket}

  @impl true
  def setopts(%{owner: owner}, :client_socket, options) do
    send(owner, {:socket_options, options})
    :ok
  end

  @impl true
  def start_handler(%{owner: owner}, :server, "auth", :client_socket, :handler_supervisor),
    do: {:ok, owner}

  @impl true
  def stop_handler(%{owner: owner}, handler_pid, reason) do
    send(owner, {:handler_stopped, handler_pid, reason})
    :ok
  end

  @impl true
  def activate_handler(_context, _handler_pid), do: :ok
end
