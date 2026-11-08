defmodule Exdock.Client.Connection.TCPClient do
  @moduledoc """
  Persistent TCP client used by an Exdock node to connect to the server.

  The client opens the SSL socket, authenticates with the configured node name
  and auth key, dynamically loads server-supplied client modules, sends
  heartbeats, reconnects when useful, and executes function calls requested by
  the server.
  """

  use GenServer
  require Logger
  alias Exdock.Client.Connection.EffectRunner
  alias Exdock.Client.Connection.Handshake
  alias Exdock.Client.Connection.Lifecycle
  alias Exdock.Client.Connection.RuntimeInstaller
  alias Exdock.Client.Connection.ServerMessage
  alias Exdock.Client.Connection.Session
  alias Exdock.Client.Connection.State
  alias Exdock.Protocol.Compatibility

  @client_version Compatibility.agent_version()
  @runtime_module Exdock.AgentRuntime

  @type t :: State.t()

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init({client_name, host, port, auth_key}) do
    # Safe decoding cannot create the module atoms carried by the authenticated
    # runtime bundle, so register the fixed allowlist before opening the socket.
    :ok = RuntimeInstaller.prepare()

    # Match the server-side token representation so the raw configured secret is
    # not retained after startup.
    auth_key = :crypto.hash(:sha256, auth_key) |> Base.encode16()

    state =
      State.new(
        host: host,
        port: port,
        client_name: client_name,
        auth_key: auth_key,
        session: Session.new()
      )

    Logger.info("Client node is [#{client_name}] with server endpoint set to [#{host}:#{port}]")
    # Defer socket work until after init returns so startup stays OTP-friendly.
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) when not is_nil(state.session) do
    if Session.connectable?(state.session) do
      case Handshake.connect(state) do
        {:ok, new_state} -> {:noreply, new_state}
        {:error, new_state} -> {:noreply, new_state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_continue(:connect, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:timeout, reconnect_timer, :try_reconnect},
        state
      ) do
    decision =
      Lifecycle.decide(
        {:reconnect_timeout, reconnect_timer == state.reconnect_timer},
        state.session,
        @client_version
      )

    case decision do
      :connect -> {:noreply, %{state | reconnect_timer: nil}, {:continue, :connect}}
      :ignore -> {:noreply, state}
    end
  end

  @impl true
  def handle_info(:heartbeat, state) do
    state =
      case Lifecycle.decide(:heartbeat, state.session, @client_version) do
        :send_heartbeat -> Handshake.heartbeat(state)
        :ignore -> state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:server_error, error}, state) do
    error
    |> then(&Lifecycle.decide({:server_error, &1}, state.session, @client_version))
    |> interpret_lifecycle(state)
  end

  @impl true
  def handle_info(:authenticate_client, state) do
    case Lifecycle.decide(:authenticate, state.session, @client_version) do
      :authenticate -> {:noreply, Handshake.authenticate(state, @client_version)}
      :ignore -> {:noreply, state}
    end
  end

  @impl true
  def handle_info({:runtime_bundle, bundle, socket}, state) do
    case Lifecycle.decide({:runtime_bundle, socket == state.socket}, state.session, @client_version) do
      :initialize_runtime ->
        {:noreply,
         Handshake.initialize_runtime(
           bundle,
           socket,
           state,
           @client_version,
           @runtime_module
         )}

      :ignore ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ssl, socket, data}, state) do
    case Lifecycle.decide({:socket_frame, socket == state.socket}, state.session, @client_version) do
      :handle_frame ->
        handle_server_message(socket, data, state)
        {:noreply, state}

      :ignore ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ssl_closed, socket}, state) do
    Lifecycle.decide({:socket_closed, socket == state.socket}, state.session, @client_version)
    |> interpret_lifecycle(state)
  end

  @impl true
  def handle_info({:ssl_error, socket, reason}, state) do
    Lifecycle.decide({:socket_error, socket == state.socket, reason}, state.session, @client_version)
    |> interpret_lifecycle(state)
  end

  defp interpret_lifecycle(:ignore, state), do: {:noreply, state}

  defp interpret_lifecycle({:disconnect, reason, reconnect?}, state) do
    {:noreply, handle_disconnection(state, reason, reconnect?)}
  end

  @spec handle_disconnection(t(), binary(), boolean()) :: t()
  defp handle_disconnection(state, reason, reconnect?),
    do: EffectRunner.disconnect(state, reason, reconnect?)

  defp handle_server_message(socket, message, state) do
    case ServerMessage.route(message) do
      {:server_error, reason} -> send(self(), {:server_error, reason})
      {:runtime_bundle, bundle} -> send(self(), {:runtime_bundle, bundle, socket})
      {:execute, command} -> EffectRunner.execute_runtime(state, command)
      {:unknown, decoded} -> Logger.error("Unknown TCP message from server: #{inspect(decoded)}")
    end
  end

  @impl true
  def handle_cast({:client_message, message}, %State{} = state),
    do: {:noreply, Handshake.send_client_message(state, message)}
end
