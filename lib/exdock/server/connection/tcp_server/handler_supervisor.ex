defmodule Exdock.Server.Connection.TCPServer.HandlerSupervisor do
  @moduledoc """
  Dynamically supervises temporary per-client connection handlers.
  """

  use DynamicSupervisor

  alias Exdock.Server.Connection.Handler

  def start_link(opts \\ [name: __MODULE__]) when is_list(opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec start_handler(
          GenServer.server(),
          String.t(),
          :ssl.sslsocket(),
          GenServer.server()
        ) :: DynamicSupervisor.on_start_child()
  def start_handler(server, auth_key, socket, supervisor \\ __MODULE__) do
    server_pid = GenServer.whereis(server)
    child_spec = Supervisor.child_spec({Handler, {server_pid, auth_key, socket}}, restart: :temporary)
    DynamicSupervisor.start_child(supervisor, child_spec)
  end
end
