defmodule Exdock.Server.Connection.Handler.SessionEffects do
  @moduledoc """
  Interprets routed client-session actions at the connection boundary.

  The connection handler owns the GenServer and socket lifecycle. This module
  coordinates authentication, runtime initialization, heartbeat timers,
  job-result correlation, transport responses, and client-message forwarding.
  """

  require Logger

  alias Exdock.Protocol.Messages.JobResult
  alias Exdock.Runtime.Coordinator
  alias Exdock.Server.Connection.ClientMessageAdapter
  alias Exdock.Server.Connection.Handler.Bootstrap
  alias Exdock.Server.Connection.Handler.State
  alias Exdock.Server.Connection.Protocol
  alias Exdock.Server.Connection.WireMessage
  alias Exdock.Server.Connection.Utils

  @heartbeat_timeout 30_000

  @type result :: {:noreply, State.t()} | {:stop, term(), State.t()}

  @spec interpret(term(), State.t(), :ssl.sslsocket(), binary()) :: result()
  def interpret(:heartbeat, state, _socket, _frame) do
    if state.heartbeat_timer, do: Process.cancel_timer(state.heartbeat_timer)
    {:noreply, %{state | heartbeat_timer: heartbeat_timer()}}
  end

  def interpret({:stop, reason}, state, _socket, _frame)
      when reason in [:version_too_old, :version_too_new, :unauthorized, :unexpected_message] do
    {:stop, reason, state}
  end

  def interpret({:stop, :unknown_message_type}, state, socket, frame) do
    Logger.warning("Unknown TCP message from [#{Utils.socket_address(socket)}]: #{inspect(frame)}")
    {:stop, :unknown_message_type, state}
  end

  def interpret({:stop, :malformed_message}, state, socket, frame) do
    Logger.warning("Malformed TCP message from [#{Utils.socket_address(socket)}]: #{inspect(frame)}")
    {:stop, :malformed_message, state}
  end

  def interpret(
        {:authenticate, client_version, auth_key, client_name},
        state,
        socket,
        _frame
      ) do
    authenticate(state, socket, client_version, auth_key, client_name)
  end

  def interpret({:initialize, bundle_version, digest, metadata}, state, _socket, _frame) do
    initialize(bundle_version, digest, metadata, state)
  end

  def interpret({:job_result, %WireMessage{} = message}, state, _socket, _frame) do
    case State.correlate_wire_result(state, message) do
      {:ok, state, job} -> adapt_and_forward_result(state, message, job)
      {:error, reason} -> reject_uncorrelated_result(state, reason)
    end
  end

  def interpret({:client_message, %WireMessage{type: :progress} = message}, state, _socket, _frame) do
    with {:ok, state} <- State.renew_dispatched_job(state, message),
         {:ok, internal} <- ClientMessageAdapter.to_internal(message) do
      forward_client_message(state, internal)
    else
      {:error, reason} -> reject_wire_message(state, reason)
    end
  end

  def interpret({:client_message, %WireMessage{} = message}, state, _socket, _frame) do
    case ClientMessageAdapter.to_internal(message) do
      {:ok, internal} -> forward_client_message(state, internal)
      {:error, reason} -> reject_wire_message(state, reason)
    end
  end

  def interpret({:client_message, message}, state, _socket, _frame) do
    forward_client_message(state, message)
  end

  defp adapt_and_forward_result(state, message, job) do
    case ClientMessageAdapter.to_job_result(message, job) do
      {:ok, %JobResult{} = internal} -> forward_client_message(state, internal)
      {:error, reason} -> reject_wire_message(state, reason)
    end
  end

  defp reject_uncorrelated_result(state, reason) do
    Logger.warning("Rejected uncorrelated job result from [#{state.session.client_name}]: #{inspect(reason)}")
    {:noreply, state}
  end

  defp reject_wire_message(state, reason) do
    Logger.warning("Rejected authenticated wire message from [#{state.session.client_name}]: #{inspect(reason)}")
    {:noreply, state}
  end

  @spec forward_client_message(State.t(), term()) :: {:noreply, State.t()}
  def forward_client_message(state, message) do
    Coordinator.client_message(state.session.client_name, message)
    {:noreply, state}
  end

  @spec send_message(:ssl.sslsocket(), term()) :: :ok | {:error, term()}
  def send_message(socket, message) do
    message = Protocol.encode_message(message)
    :ssl.send(socket, message)
  rescue
    exception -> {:error, {:exception, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp authenticate(state, socket, version, auth_key, client_name) do
    case Bootstrap.authenticate(state, version, auth_key, client_name) do
      {:ok, state, bundle} ->
        announce_client(socket)
        send_message(socket, {:runtime_bundle, bundle})
        {:noreply, state}

      {:error, reason, state} ->
        authentication_error(reason, state, version, client_name)
    end
  end

  defp authentication_error(
         {:version_requirement, requirement} = reason,
         state,
         version,
         _client_name
       ) do
    Logger.warning("Disconnecting client due to version requirement: #{inspect(version)}, expected: #{requirement}")

    {:stop, reason, state}
  end

  defp authentication_error(:invalid_auth, state, _version, _client_name),
    do: {:stop, :invalid_auth, state}

  defp authentication_error(:duplicate_name, state, _version, client_name) do
    Logger.warning("Disconnecting client due to duplicate name: #{client_name}")
    {:stop, :duplicate_name, state}
  end

  defp authentication_error(:invalid_name, state, _version, client_name) do
    Logger.warning("Disconnecting client due to invalid name: #{client_name}")
    {:stop, :invalid_name, state}
  end

  defp authentication_error(:load_module_fail, state, _version, _client_name),
    do: {:stop, :load_module_fail, state}

  defp initialize(bundle_version, digest, metadata, state) do
    case Bootstrap.initialize(state, bundle_version, digest) do
      {:ok, state} ->
        initialization_time =
          DateTime.diff(DateTime.utc_now(), state.connected_at, :millisecond)

        Logger.info("Client [#{state.session.client_name}] initialization completed in #{initialization_time}ms")

        send(state.parent_pid, {:client_ready, self(), state.session.client_name, metadata})
        {:noreply, %{state | heartbeat_timer: heartbeat_timer()}}

      {:error, :runtime_bundle_mismatch, state} ->
        {:stop, :runtime_bundle_mismatch, state}
    end
  end

  defp announce_client(socket) do
    case Utils.client_info(socket) do
      nil ->
        :ok

      client_info ->
        Logger.info("New client connected: port=#{inspect(client_info.port)} address=#{inspect(client_info.address)}")
    end
  end

  defp heartbeat_timer do
    Process.send_after(self(), {:heartbeat, :timeout}, @heartbeat_timeout)
  end
end
