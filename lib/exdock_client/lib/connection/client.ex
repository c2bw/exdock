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
  alias Exdock.Client.Connection.ServerMessage
  alias Exdock.Client.Connection.Session
  alias Exdock.Client.Connection.State
  alias Exdock.Protocol.{Channel, Compatibility}

  @client_version Compatibility.agent_version()
  @runtime_module Exdock.AgentRuntime

  @type t :: State.t()

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init({client_name, host, port, auth_key}) do
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
  def handle_info({:timeout, timer, :wire_tick}, %{heartbeat_timer: timer} = state) do
    {:noreply, Handshake.heartbeat(state)}
  end

  def handle_info({:timeout, _timer, :wire_tick}, state), do: {:noreply, state}

  @impl true
  def handle_info({:ssl, socket, bytes}, %{socket: socket, wire: wire} = state) when not is_nil(wire) do
    case Channel.feed(wire, bytes, &state.transport.send(socket, &1)) do
      {:ok, wire, events} ->
        state = apply_events(events, %{state | wire: wire})

        case state.socket && state.transport.activate(socket) do
          {:error, reason} -> {:noreply, EffectRunner.disconnect(state, "SSL activation: #{inspect(reason)}")}
          _ -> {:noreply, state}
        end

      {:error, reason} ->
        {:noreply, EffectRunner.disconnect(state, "NodeWire receive: #{inspect(reason)}")}
    end
  end

  def handle_info({:ssl, _socket, _bytes}, state), do: {:noreply, state}

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

  defp apply_events([], state), do: state
  defp apply_events(_events, %{socket: nil} = state), do: state

  defp apply_events([:established | events], state) do
    apply_events(events, Handshake.authenticate(state, @client_version))
  end

  defp apply_events([event | events], state) do
    state =
      case ServerMessage.route(event) do
        {:server_error, reason} ->
          {:noreply, state} =
            Lifecycle.decide({:server_error, reason}, state.session, @client_version)
            |> interpret_lifecycle(state)

          state

        {:runtime_bundle, bundle} ->
          if Session.in_phase?(state.session, :authenticating),
            do: Handshake.initialize_runtime(bundle, state, @client_version, @runtime_module),
            else: EffectRunner.disconnect(state, "Unexpected runtime bundle")

        {:execute, command} ->
          if Session.in_phase?(state.session, :ready) do
            EffectRunner.execute_runtime(state, command)
            state
          else
            EffectRunner.disconnect(state, "Command received before runtime readiness")
          end
      end

    apply_events(events, state)
  end

  @impl true
  def format_status(status) do
    status
    |> Map.update(:state, nil, &%{&1 | auth_key: :redacted, wire: :redacted})
    |> Map.replace(:message, :redacted)
    |> Map.replace(:log, [])
  end

  @impl true
  def handle_cast({:client_message, message}, %State{} = state),
    do: {:noreply, Handshake.send_client_message(state, message)}
end
