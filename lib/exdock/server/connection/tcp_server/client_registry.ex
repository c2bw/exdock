defmodule Exdock.Server.Connection.TCPServer.ClientRegistry do
  @moduledoc """
  Monitored registry for authenticated TCP client handlers.

  Handler termination automatically releases its node name and emits the
  corresponding connection lifecycle event.
  """

  use GenServer

  alias Exdock.NodeId
  alias Exdock.Server.Connection.TCPServer.ClientLifecycle

  defstruct clients: %{}, monitors: %{}, lifecycle: ClientLifecycle

  @type registration_error :: :invalid | :duplicate
  @type server :: GenServer.server()

  def start_link(opts \\ [name: __MODULE__]) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    genserver_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, genserver_opts)
  end

  @spec register(String.t(), pid(), server()) :: :ok | {:error, registration_error()}
  def register(client_name, handler, server \\ __MODULE__) do
    GenServer.call(server, {:register, client_name, handler})
  end

  @spec fetch(String.t(), server()) :: {:ok, pid()} | :error
  def fetch(client_name, server \\ __MODULE__) do
    GenServer.call(server, {:fetch, client_name})
  end

  @spec unregister(String.t(), pid(), server()) :: :ok
  def unregister(client_name, handler, server \\ __MODULE__) do
    GenServer.call(server, {:unregister, client_name, handler})
  end

  @spec connected_clients(server()) :: %{String.t() => pid()}
  def connected_clients(server \\ __MODULE__) do
    GenServer.call(server, :connected_clients)
  end

  @impl true
  def init(opts) do
    {:ok, %__MODULE__{lifecycle: Keyword.get(opts, :lifecycle, ClientLifecycle)}}
  end

  @impl true
  def handle_call({:register, client_name, handler}, _from, state) do
    case validate_registration(state, client_name, handler) do
      :ok ->
        monitor = Process.monitor(handler)
        client = %{pid: handler, monitor: monitor}

        {:reply, :ok,
         %{
           state
           | clients: Map.put(state.clients, client_name, client),
             monitors: Map.put(state.monitors, monitor, client_name)
         }}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:fetch, client_name}, _from, state) do
    reply =
      case Map.fetch(state.clients, client_name) do
        {:ok, %{pid: handler}} -> {:ok, handler}
        :error -> :error
      end

    {:reply, reply, state}
  end

  def handle_call({:unregister, client_name, handler}, _from, state) do
    case Map.get(state.clients, client_name) do
      %{pid: ^handler, monitor: monitor} ->
        Process.demonitor(monitor, [:flush])
        state.lifecycle.disconnected(client_name)
        {:reply, :ok, delete_client(state, client_name, monitor)}

      _missing_or_replaced ->
        {:reply, :ok, state}
    end
  end

  def handle_call(:connected_clients, _from, state) do
    clients = Map.new(state.clients, fn {name, %{pid: handler}} -> {name, handler} end)
    {:reply, clients, state}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _handler, _reason}, state) do
    case Map.fetch(state.monitors, monitor) do
      {:ok, client_name} ->
        state.lifecycle.disconnected(client_name)
        {:noreply, delete_client(state, client_name, monitor)}

      :error ->
        {:noreply, state}
    end
  end

  defp validate_registration(state, client_name, handler) do
    with true <- is_pid(handler),
         :ok <- validate_name(client_name),
         false <- Map.has_key?(state.clients, client_name) do
      :ok
    else
      true -> {:error, :duplicate}
      _invalid -> {:error, :invalid}
    end
  end

  defp validate_name(client_name) when is_binary(client_name) do
    case NodeId.validate(client_name) do
      :ok -> :ok
      {:error, _reason} -> {:error, :invalid}
    end
  end

  defp validate_name(_client_name), do: {:error, :invalid}

  defp delete_client(state, client_name, monitor) do
    %{
      state
      | clients: Map.delete(state.clients, client_name),
        monitors: Map.delete(state.monitors, monitor)
    }
  end
end
