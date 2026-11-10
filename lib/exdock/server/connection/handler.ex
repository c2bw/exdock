defmodule Exdock.Server.Connection.Handler do
  @moduledoc """
  Per-client SSL connection handler for the server.

  A handler owns one socket from accept through termination. It authenticates the
  client, loads the server-provided client modules, forwards client messages into
  `Exdock.Server`, and enforces heartbeat, initialization, and remote-job
  timeouts.
  """

  use GenServer
  require Logger
  alias Exdock.Protocol.Channel
  alias Exdock.Protocol.Messages.JobResult
  alias Exdock.Protocol.Message
  alias Exdock.Server.Connection.Handler.FrameRouter
  alias Exdock.Server.Connection.Handler.Lifecycle
  alias Exdock.Server.Connection.Handler.SessionEffects
  alias Exdock.Server.Connection.Handler.State, as: HandlerState
  alias Exdock.Server.Connection.Session
  alias Exdock.Server.Connection.Utils
  alias Exdock.Server.Jobs.Job

  @initialization_timeout 10_000
  @command_send_timeout 6_000
  @type t :: HandlerState.t()

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init({parent, auth_key, socket}) do
    state = HandlerState.new(parent, auth_key, socket)

    # The client must complete hello/auth/module-loading quickly; otherwise the
    # connection is closed and any registered node name is released.
    schedule_initialization_timeout()
    {:ok, state}
  end

  @doc """
    Stop the handler and close its client socket.
  """
  @spec stop(pid(), term()) :: :ok
  def stop(handler_pid, reason \\ :normal) do
    GenServer.stop(handler_pid, reason)
  end

  @doc """
  Send a command to the connected client and acknowledge the socket write.

  A command is tracked for its remote timeout only after the SSL transport
  accepts the frame.
  """
  @spec send_command(pid(), Job.t()) :: :ok | {:error, term()}
  def send_command(handler_pid, %Job{} = job) do
    GenServer.call(handler_pid, {:send_command, job}, @command_send_timeout)
  end

  @doc false
  @spec activate_socket(pid(), pos_integer()) :: :ok | {:error, term()}
  def activate_socket(handler_pid, max_frame_size) do
    GenServer.call(handler_pid, {:activate_socket, max_frame_size})
  end

  @impl true
  def handle_call({:activate_socket, max_frame_size}, _from, state) do
    with {:ok, wire, []} <- Channel.start(:server, &:ssl.send(state.socket, &1), max_frame_size),
         :ok <- :ssl.setopts(state.socket, active: :once) do
      schedule_wire_tick()
      {:reply, :ok, %{state | wire: wire}}
    else
      {:error, reason} -> {:stop, {:socket_activation_failed, reason}, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:send_command, %Job{} = job}, _from, state) do
    if Session.ready?(state.session) do
      command = Message.command(job.id, job.name, job.parameters)

      case SessionEffects.send_message(state, {:command, command}) do
        {:ok, state} ->
          {:reply, :ok, track_dispatched_job(state, job)}

        {:error, {:transport_error, reason}} = error ->
          {:stop, {:socket_send_failed, reason}, error, %{state | wire: nil}}

        {:error, _} = error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :client_not_ready}, state}
    end
  end

  @impl true
  def handle_info(:is_client_ready, state) do
    Lifecycle.decide(:initialization_timeout, state.session)
    |> interpret_lifecycle(state)
  end

  @impl true
  def handle_info({:ssl, socket, bytes}, %{socket: socket, wire: wire} = state) when not is_nil(wire) do
    case Channel.feed(wire, bytes, &:ssl.send(socket, &1)) do
      {:ok, wire, events} -> apply_events(events, %{state | wire: wire}) |> activate_after_frame()
      {:error, reason} -> {:stop, reason, %{state | wire: nil}}
    end
  end

  def handle_info({:ssl, _socket, _bytes}, state), do: {:noreply, state}

  @impl true
  def handle_info({:ssl_closed, _socket}, state) do
    Lifecycle.decide(:socket_closed, state.session)
    |> interpret_lifecycle(state)
  end

  @impl true
  def handle_info({:ssl_error, socket, reason}, state) do
    Logger.error("TCP error for client #{inspect(Utils.client_info(socket))}: #{inspect(reason)}")

    Lifecycle.decide({:socket_error, reason}, state.session)
    |> interpret_lifecycle(state)
  end

  @impl true
  def handle_info(:wire_tick, state) do
    case Channel.tick(state.wire, &:ssl.send(state.socket, &1)) do
      {:ok, wire, []} ->
        schedule_wire_tick()
        {:noreply, %{state | wire: wire}}

      {:error, reason} ->
        {:stop, reason, %{state | wire: nil}}
    end
  end

  @impl true
  def handle_info({:remote_job_timeout, job_id, token}, state) do
    case expire_dispatched_job(state, job_id, token) do
      {:ok, state, %JobResult{job: %Job{name: name}} = message} ->
        Logger.error("Remote job [#{name}:#{job_id}] timed out for client [#{state.session.client_name}]")

        {:noreply, state} = SessionEffects.forward_client_message(state, message)
        # An unresponsive command may still change Docker state. Reconnect and
        # wait for agent work to drain before accepting a fresh node snapshot.
        {:stop, :client_job_timeout, state}

      {:error, :unknown_job} ->
        {:noreply, state}
    end
  end

  @impl true
  def format_status(status) do
    status
    |> Map.update(:state, nil, &%{&1 | auth_key: :redacted, wire: :redacted})
    |> Map.replace(:message, :redacted)
    |> Map.replace(:log, [])
  end

  @impl true
  def terminate(reason, %{socket: socket, session: session} = state) do
    client_name = if Session.registered?(session), do: session.client_name
    termination_message = termination_log_message(socket, client_name, reason)

    if normal_termination?(reason) do
      Logger.debug(termination_message)
    else
      Logger.warning(termination_message)

      if state.wire && NodeWire.Session.status(state.wire) == :established,
        do: SessionEffects.send_message(state, {:error, reason})
    end

    # :ssl.close/1 is idempotent, so termination can always close defensively.
    :ssl.close(socket)
  end

  defp termination_log_message(socket, client_name, reason) do
    "Connection handler for [#{Utils.socket_address(socket)} => #{client_name}] terminating: #{inspect(reason)}"
  end

  defp normal_termination?(:normal), do: true
  defp normal_termination?(_reason), do: false

  defp interpret_lifecycle(:continue, state), do: {:noreply, state}
  defp interpret_lifecycle({:stop, reason}, state), do: {:stop, reason, state}

  defp apply_events([], state), do: {:noreply, state}
  defp apply_events([:established | events], state), do: apply_events(events, state)

  defp apply_events([event | events], state) do
    case state.session |> FrameRouter.route(event) |> SessionEffects.interpret(state, state.socket, <<>>) do
      {:noreply, state} -> apply_events(events, state)
      {:stop, _, _} = stop -> stop
    end
  end

  defp schedule_wire_tick, do: Process.send_after(self(), :wire_tick, Channel.tick_interval())

  defp activate_after_frame({:noreply, state}), do: activate_next_frame(state)
  defp activate_after_frame(result), do: result

  defp activate_next_frame(state) do
    case :ssl.setopts(state.socket, active: :once) do
      :ok -> {:noreply, state}
      {:error, reason} -> {:stop, {:socket_activation_failed, reason}, state}
    end
  end

  defp schedule_initialization_timeout do
    Process.send_after(self(), :is_client_ready, @initialization_timeout)
  end

  @doc false
  defdelegate track_dispatched_job(state, job), to: HandlerState

  @doc false
  defdelegate correlate_wire_result(state, message), to: HandlerState

  @doc false
  defdelegate expire_dispatched_job(state, job_id, token), to: HandlerState
end
