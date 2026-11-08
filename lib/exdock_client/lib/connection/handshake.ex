defmodule Exdock.Client.Connection.Handshake do
  @moduledoc """
  Orchestrates SSL connection setup, authentication, and runtime readiness.

  All transport sends and session transitions used by the handshake live here,
  leaving the TCP GenServer responsible for mailbox routing.
  """

  require Logger

  alias Exdock.Client.Connection.EffectRunner
  alias Exdock.Client.Connection.Metadata
  alias Exdock.Client.Connection.Protocol
  alias Exdock.Client.Connection.RuntimeInstaller
  alias Exdock.Client.Connection.Session
  alias Exdock.Client.Connection.State

  @heartbeat_interval 10_000
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
      packet: 4
    ]

    case state.transport.connect(state.host, state.port, ssl_opts, @send_timeout) do
      {:ok, socket} ->
        Logger.info("Established SSL connection with #{state.host}:#{state.port}")

        state =
          state
          |> EffectRunner.cancel_reconnect()
          |> then(
            &%{
              &1
              | socket: socket,
                reconnect_timer: nil,
                heartbeat_timer: schedule_heartbeat(state)
            }
          )
          |> transition_session!(:socket_connected)

        send(self(), :authenticate_client)
        {:ok, state}

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
      :noop -> state
      :ok -> state
      {:error, reason} -> EffectRunner.disconnect(state, "authenticate_client: TCP error: #{reason}")
    end
  end

  @spec initialize_runtime(map(), term(), State.t(), String.t(), module()) :: State.t()
  def initialize_runtime(bundle, socket, %State{} = state, client_version, runtime_module)
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

        case send_message(state, socket, {:ready, ready}) do
          :noop -> state
          :ok -> transition_session!(state, :ready)
          {:error, reason} -> EffectRunner.disconnect(state, "client_ready: TCP error: #{reason}")
        end

      {:error, reason} ->
        EffectRunner.disconnect(state, "failed to install runtime bundle: #{inspect(reason)}")
    end
  end

  @spec heartbeat(State.t()) :: State.t()
  def heartbeat(%State{} = state) do
    case send_message(state, {:heartbeat}) do
      :noop -> state
      :ok -> %{state | heartbeat_timer: schedule_heartbeat(state)}
      {:error, reason} -> EffectRunner.disconnect(state, "heartbeat: TCP error: #{reason}")
    end
  end

  @spec send_client_message(State.t(), term()) :: State.t()
  def send_client_message(%State{} = state, message) do
    # Results from work started on a previous connection must not be sent into
    # the new connection's authentication or bundle exchange.
    result = if Session.in_phase?(state.session, :ready), do: send_message(state, state.socket, message), else: :noop

    case result do
      :noop -> state
      :ok -> state
      {:error, reason} -> EffectRunner.disconnect(state, "client_message: TCP error: #{reason}")
    end
  end

  defp schedule_heartbeat(state), do: state.timer.heartbeat(@heartbeat_interval)

  defp transition_session!(%State{} = state, event) do
    case Session.transition(state.session, event) do
      {:ok, session} -> %{state | session: session}
      {:error, reason} -> raise ArgumentError, "invalid client connection transition: #{inspect(reason)}"
    end
  end

  defp send_message(state, message), do: send_message(state, state.socket, message)

  defp send_message(state, socket, message) do
    encoded = Protocol.encode_message(message)

    case socket do
      nil -> :noop
      socket -> state.transport.send(socket, encoded)
    end
  end
end
