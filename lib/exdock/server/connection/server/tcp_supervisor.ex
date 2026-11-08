defmodule Exdock.Server.Connection.TCPServer.TCPSupervisor do
  @moduledoc """
  Supervises the TCP listener and bounded handshake workers.

  Socket ownership and accept-loop failures belong to `Listener`; this module
  only declares their restart relationship.
  """

  use Supervisor

  alias Exdock.Server.Connection.TCPServer
  alias Exdock.Server.Connection.TCPServer.{HandlerSupervisor, Listener}

  @max_handshake_workers 128

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init({server, auth_key, port}) do
    init({server, HandlerSupervisor, auth_key, port, []})
  end

  def init({server, handler_supervisor, auth_key, port}) do
    init({server, handler_supervisor, auth_key, port, []})
  end

  def init({server, handler_supervisor, auth_key, port, connection_opts}) when is_list(connection_opts) do
    children = [
      {Task.Supervisor, name: TCPServer.TaskSupervisor, max_children: @max_handshake_workers},
      {Listener, {server, handler_supervisor, auth_key, port, connection_opts}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
