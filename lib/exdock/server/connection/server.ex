defmodule Exdock.Server.Connection.TCPServer do
  @moduledoc """
  Command-dispatch and readiness boundary for connected Exdock client nodes.

  Handler supervision and connection lookup are owned by dedicated processes;
  this server only validates registry membership before dispatching commands or
  accepting a ready acknowledgement.
  """

  use GenServer

  require Logger

  alias Exdock.Server.Connection.Handler
  alias Exdock.Server.Connection.TCPServer.{ClientLifecycle, ClientRegistry}
  alias Exdock.Server.Jobs.Job

  @command_dispatch_timeout 7_000

  defstruct registry: ClientRegistry, native_metadata: %{}, native_ready: %{}, registry_monitor: nil

  @type t :: %__MODULE__{registry: GenServer.server()}

  @type command_error ::
          :server_unavailable
          | :node_not_connected
          | {:command_send_failed, term()}

  def start_link(opts \\ [name: __MODULE__]) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    # This child starts after all old socket owners have been shut down during
    # a connection-tree restart, and before new handlers can become ready.
    # The registry that owned their monitors may already be gone.
    if Keyword.get(opts, :reset_connections, false), do: ClientLifecycle.reset()
    if match?({:nodewire, _}, Keyword.get(opts, :registry)), do: send(self(), :watch_native_registry)
    {:ok, %__MODULE__{registry: Keyword.get(opts, :registry, ClientRegistry)}}
  end

  @doc """
  Send one validated job command to a connected agent.
  """
  @spec send_command(String.t(), Job.t(), GenServer.server()) :: :ok | {:error, command_error()}
  def send_command(node, %Job{} = job, server \\ __MODULE__) do
    call_tcp_server(server, {:send_command, node, job})
  end

  @spec connected_clients() :: %{String.t() => pid()}
  def connected_clients do
    call_tcp_server(__MODULE__, :connected_clients)
  end

  @impl true
  def handle_call({:send_command, node, %Job{} = job}, _from, state) do
    case dispatch_command(state, node, job) do
      :ok ->
        {:reply, :ok, state}

      {:error, :node_not_connected} = error ->
        Logger.error("Failed to message [#{node}], reason: node is not connected")
        {:reply, error, state}

      {:error, reason, handler} ->
        terminate_failed_handler(state, node, handler)
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:connected_clients, _, %{registry: {:nodewire, server}} = state) do
    clients = NodeWire.Server.connections(server) |> Enum.filter(&(&1.phase == :ready)) |> Map.new(&{&1.identity, &1.owner})
    {:reply, clients, state}
  end

  def handle_call(:connected_clients, _from, state) do
    {:reply, ClientRegistry.connected_clients(state.registry), state}
  end

  @impl true
  def handle_info({:client_ready, handler, client_name, metadata}, state)
      when is_pid(handler) and is_binary(client_name) and is_map(metadata) do
    case ClientRegistry.fetch(client_name, state.registry) do
      {:ok, ^handler} ->
        ClientLifecycle.ready(client_name, metadata)

      _missing_or_replaced ->
        Logger.warning("Ignoring ready acknowledgement from unregistered client [#{client_name}]")
    end

    {:noreply, state}
  end

  def handle_info(:watch_native_registry, %{registry: {:nodewire, server}} = s) do
    registry =
      try do
        NodeWire.Server.child(server, NodeWire.Server.Registry)
      catch
        :exit, _ -> nil
      end

    if is_pid(registry) do
      {:noreply, %{s | registry_monitor: Process.monitor(registry)}}
    else
      Process.send_after(self(), :watch_native_registry, 20)
      {:noreply, s}
    end
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{registry_monitor: ref} = s) do
    ClientLifecycle.reset()
    send(self(), :watch_native_registry)
    {:noreply, %{s | registry_monitor: nil, native_metadata: %{}, native_ready: %{}}}
  end

  def handle_info({:native_metadata, id, metadata}, s),
    do: {:noreply, native_ready(%{s | native_metadata: Map.put(s.native_metadata, id, metadata)}, id)}

  def handle_info({:nodewire, :ready, conn, _}, s),
    do: {:noreply, native_ready(%{s | native_ready: Map.put(s.native_ready, conn.id, conn)}, conn.id)}

  def handle_info({:nodewire, :disconnected, conn, _}, s) do
    ClientLifecycle.disconnected(conn.identity)
    {:noreply, %{s | native_metadata: Map.delete(s.native_metadata, conn.id), native_ready: Map.delete(s.native_ready, conn.id)}}
  end

  def handle_info({:nodewire, _, _, _}, s), do: {:noreply, s}

  defp native_ready(s, id) do
    with {:ok, conn} <- Map.fetch(s.native_ready, id), {:ok, metadata} <- Map.fetch(s.native_metadata, id) do
      ClientLifecycle.ready(conn.identity, metadata)
      %{s | native_metadata: Map.delete(s.native_metadata, id), native_ready: Map.delete(s.native_ready, id)}
    else
      _ -> s
    end
  end

  defp dispatch_command(%{registry: {:nodewire, server}}, node, %Job{} = job) do
    command = Exdock.Protocol.Message.command(job.id, job.name, job.parameters)

    case NodeWire.Server.send(server, node, {:command, command}, on_sent: {:track_job, job}) do
      :ok -> :ok
      {:error, :not_connected} -> {:error, :node_not_connected}
      {:error, reason} -> {:error, {:command_send_failed, reason}, nil}
    end
  end

  defp dispatch_command(%__MODULE__{} = state, node, %Job{} = job) do
    case ClientRegistry.fetch(node, state.registry) do
      {:ok, handler} ->
        case send_command_to_handler(handler, job) do
          :ok -> :ok
          {:error, reason} -> {:error, reason, handler}
        end

      :error ->
        {:error, :node_not_connected}
    end
  end

  defp send_command_to_handler(handler, %Job{} = job) do
    case Handler.send_command(handler, job) do
      :ok -> :ok
      {:error, reason} -> {:error, {:command_send_failed, reason}}
    end
  catch
    :exit, reason -> {:error, {:command_send_failed, {:handler_exit, reason}}}
  end

  defp terminate_failed_handler(%{registry: {:nodewire, _}}, _, _), do: :ok

  defp terminate_failed_handler(%__MODULE__{} = state, client_name, handler) do
    # A call timeout does not terminate its callee. Wait for this exact socket
    # owner to die before releasing its name, even if it is suspended or busy.
    monitor = Process.monitor(handler)
    Process.exit(handler, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^handler, _reason} -> :ok
    end

    # The registry may already have processed DOWN and registered a replacement.
    # Its pid check prevents this cleanup from unregistering the new owner.
    ClientRegistry.unregister(client_name, handler, state.registry)
  end

  defp call_tcp_server(server, message) do
    GenServer.call(server, message, @command_dispatch_timeout)
  catch
    :exit, _reason -> {:error, :server_unavailable}
  end
end
