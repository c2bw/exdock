defmodule Exdock.Client.Connection.Handshake do
  @moduledoc """
  Orchestrates SSL connection setup, authentication, and runtime readiness.

  All transport sends and session transitions used by the handshake live here,
  leaving the TCP GenServer responsible for mailbox routing.
  """

  require Logger

  alias Exdock.Client.Connection.EffectRunner
  alias Exdock.Client.Connection.Metadata
  alias Exdock.Protocol.Channel
  alias Exdock.Client.Connection.RuntimeInstaller
  alias Exdock.Client.Connection.Session
  alias Exdock.Client.Connection.State

  @send_timeout 3_000

  @spec connect(State.t()) :: {:ok, State.t()} | {:error, State.t()}
  def connect(%State{} = state) do
    Logger.info("Attempting to connect to the server..")
    state = transition_session!(state, :connect)

    ssl_opts = [
      # Certificate verification is intentionally disabled for deployments with
      # a trusted or externally authenticated server path. AUTH_KEY authenticates
      # this client, not the server. See docs/UNVERIFIED_TLS_ACCEPTED_RISK_SPEC.md.
      verify: :verify_none,
      mode: :binary,
      packet: :raw,
      active: false,
      send_timeout: @send_timeout,
      send_timeout_close: true
    ]

    case state.transport.connect(state.host, state.port, ssl_opts, @send_timeout) do
      {:ok, socket} ->
        Logger.info("Established SSL connection with #{state.host}:#{state.port}")

        state = state |> EffectRunner.cancel_reconnect() |> Map.put(:socket, socket)

        with {:ok, wire, []} <- Channel.start(:client, &state.transport.send(socket, &1)),
             :ok <- state.transport.activate(socket) do
          state = %{state | wire: wire, heartbeat_timer: schedule_heartbeat(state)}
          {:ok, transition_session!(state, :socket_connected)}
        else
          {:error, reason} -> {:error, EffectRunner.disconnect(state, "NodeWire setup: #{inspect(reason)}")}
        end

      {:error, reason} ->
        Logger.error("Failed to establish SSL connection with [#{state.host}:#{state.port}] [#{inspect(reason)}]")

        state =
          state
          |> then(&%{&1 | socket: nil, heartbeat_timer: nil})
          |> transition_session!(:disconnect)
          |> EffectRunner.schedule_reconnect()

        {:error, state}
    end
  end

  @spec authenticate(State.t(), String.t()) :: State.t()
  def authenticate(%State{} = state, client_version) when is_binary(client_version) do
    Logger.info("Authenticating client...")

    hello = %{
      "agent_version" => client_version,
      "auth_token" => state.auth_key,
      "node" => state.client_name
    }

    case send_message(state, {:hello, hello}) do
      {:ok, state} -> state
      {:error, reason} -> EffectRunner.disconnect(state, "authenticate_client: NodeWire error: #{inspect(reason)}")
    end
  end

  @spec initialize_runtime(map(), State.t(), String.t(), module()) :: State.t()
  def initialize_runtime(bundle, %State{} = state, client_version, runtime_module)
      when is_map(bundle) and is_binary(client_version) and is_atom(runtime_module) do
    Logger.info("Initializing client..")
    Logger.debug("Loading runtime bundle #{bundle["version"]}")

    state = transition_session!(state, :runtime_bundle_received)

    case RuntimeInstaller.install(bundle, state.client_name, runtime_module) do
      :ok ->
        Logger.info("Client initialized successfully.")

        ready = %{
          "bundle_version" => bundle["version"],
          "digest" => bundle["digest"],
          "metadata" => Metadata.collect(client_version)
        }

        case send_message(state, {:ready, ready}) do
          {:ok, state} -> transition_session!(state, :ready)
          {:error, reason} -> EffectRunner.disconnect(state, "client_ready: NodeWire error: #{inspect(reason)}")
        end

      {:error, reason} ->
        EffectRunner.disconnect(state, "failed to install runtime bundle: #{inspect(reason)}")
    end
  end

  @spec heartbeat(State.t()) :: State.t()
  def heartbeat(%State{} = state) do
    case Channel.tick(state.wire, &state.transport.send(state.socket, &1)) do
      {:ok, wire, []} -> %{state | wire: wire, heartbeat_timer: schedule_heartbeat(state)}
      {:error, reason} -> EffectRunner.disconnect(state, "NodeWire tick: #{inspect(reason)}")
    end
  end

  @spec send_client_message(State.t(), term()) :: State.t()
  def send_client_message(%State{} = state, message) do
    if Session.in_phase?(state.session, :ready) do
      case send_message(state, message) do
        {:ok, state} ->
          state

        {:error, %NodeWire.Session.Error{code: code}}
        when code in [:frame_too_large, :invalid_payload] ->
          send_size_failure(state, message)

        {:error, reason} ->
          EffectRunner.disconnect(state, "NodeWire send: #{inspect(reason)}")
      end
    else
      state
    end
  end

  defp send_size_failure(state, {:result, %{"kind" => kind} = result}) do
    data =
      if kind == "node_refresh" do
        empty = %{"ok" => [], "errored" => []}
        %{"containers" => empty, "images" => empty}
      end

    failure = %{result | "data" => data, "error" => "Result could not be encoded within the agent wire limits"}

    case send_message(state, {:result, failure}) do
      {:ok, state} -> state
      {:error, reason} -> EffectRunner.disconnect(state, "NodeWire send: #{inspect(reason)}")
    end
  end

  defp send_size_failure(state, _message), do: state

  defp schedule_heartbeat(state), do: state.timer.heartbeat(Channel.tick_interval())

  defp transition_session!(%State{} = state, event) do
    case Session.transition(state.session, event) do
      {:ok, session} -> %{state | session: session}
      {:error, reason} -> raise ArgumentError, "invalid client connection transition: #{inspect(reason)}"
    end
  end

  defp send_message(state, message) do
    with {:ok, wire, []} <- Channel.send_event(state.wire, message, &state.transport.send(state.socket, &1)) do
      {:ok, %{state | wire: wire}}
    end
  end
end
