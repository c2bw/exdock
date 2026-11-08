defmodule Exdock.Server.Connection.Supervisor do
  @moduledoc """
  Supervises the connection registry, command server, handlers, and listener.

  Dependency order ensures a registry or command-server restart also replaces
  downstream handlers and socket owners that reference it. The command server
  resets authoritative connection state before the listener accepts new clients.
  """

  use Supervisor

  alias Exdock.Server.Connection.TCPServer
  alias Exdock.Server.Connection.TCPServer.{ClientRegistry, HandlerSupervisor, TCPSupervisor}

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init({auth_key, port}) do
    init({auth_key, port, max_frame_size: Application.fetch_env!(:exdock, :tcp_max_frame_size)})
  end

  def init({auth_key, port, connection_opts}) when is_list(connection_opts) do
    children = [
      {ClientRegistry, name: ClientRegistry},
      {TCPServer, name: TCPServer, registry: ClientRegistry, reset_connections: true},
      {HandlerSupervisor, name: HandlerSupervisor},
      {TCPSupervisor, {TCPServer, HandlerSupervisor, auth_token(auth_key), port, connection_opts}}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp auth_token(auth_key), do: :crypto.hash(:sha256, auth_key) |> Base.encode16()
end
