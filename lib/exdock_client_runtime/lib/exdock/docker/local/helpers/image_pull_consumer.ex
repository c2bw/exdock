defmodule Exdock.Docker.Local.Helpers.ImagePullConsumer do
  @moduledoc """
  Stream consumer for Docker image pull progress.

  Docker pull responses arrive as newline-delimited JSON records over arbitrary
  transport chunks. This GenServer buffers those chunks, throttles job update
  messages, and reports final completion or failure back to the caller.
  """

  alias Exdock.ClientLib, as: Client
  alias Exdock.ClientLib.Utils
  alias Exdock.AgentRuntime.Size
  alias Exdock.Docker.Error
  alias Exdock.Docker.Local.Helpers.ImagePullStream
  require Logger
  use GenServer
  @compile {:no_warn_undefined, Exdock.AgentRuntime.Size}

  @inactivity_timeout 300_000
  @send_interval 50

  def start_link({name, {caller_pid, job_name, job_id}}) do
    start_link({name, {caller_pid, job_name, job_id}, []})
  end

  def start_link({name, {caller_pid, job_name, job_id}, opts}) when is_list(opts) do
    dispatcher = Keyword.get(opts, :dispatcher, Exdock.ClientLib.CommandDispatcher)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    GenServer.start_link(__MODULE__, {caller_pid, job_name, job_id, dispatcher, clock}, name: name)
  end

  # Initialize the GenServer with the caller_pid
  def init({caller_pid, job_name, job_id, dispatcher, clock}) do
    # `last_send` throttles progress broadcasts so a fast pull stream does not
    # overwhelm PubSub or the LiveView process.
    initial_state = %{
      caller_pid: caller_pid,
      job_name: job_name,
      job_id: job_id,
      dispatcher: dispatcher,
      clock: clock,
      last_send: nil,
      stream: ImagePullStream.new()
    }

    {:ok, initial_state, @inactivity_timeout}
  end

  # Handle incoming messages
  def handle_info({:hackney_response, _ref, {:error, reason}}, state),
    do: stop_with_stream_error(reason, state)

  def handle_info({:hackney_response, _ref, :done}, state), do: complete_stream(state)

  def handle_info({:hackney_response, _ref, body}, state) when is_binary(body) do
    {:noreply, consume_stream(state, body), @inactivity_timeout}
  end

  def handle_info({:hackney_response, _ref, body}, state),
    do: {:noreply, consume_stream(state, body), @inactivity_timeout}

  def handle_info(:done, state), do: complete_stream(state)

  def handle_info({:stream_request_result, {:ok, _response}}, state),
    do: {:noreply, state, @inactivity_timeout}

  def handle_info({:stream_request_result, {:error, reason}}, state) do
    error = Utils.docker_error({:image_pull, :stream_request}, reason)
    Logger.error("GenServer: Image Pull: #{Error.message(error)}")
    send(state.caller_pid, {:image_pull_error, error})
    {:stop, :normal, state}
  end

  def handle_info({:stream_error, reason}, state), do: stop_with_stream_error(reason, state)

  def handle_info(:timeout, state) do
    Logger.warning("GenServer: Image Pull: inactivity timeout")
    error = Error.new({:image_pull, :stream}, :timeout, message: "Image pull stream timed out")
    send(state.caller_pid, {:image_pull_error, error})
    {:stop, :normal, state}
  end

  def handle_info(msg, state) do
    Logger.warning("GenServer: Image Pull: unhandled message: #{inspect(msg)}")
    {:noreply, state, @inactivity_timeout}
  end

  defp complete_stream(state) do
    {stream, events, result} = ImagePullStream.finish(state.stream)

    state =
      state
      |> Map.put(:stream, stream)
      |> publish_stream_events(events)

    case result do
      :ok -> send(state.caller_pid, :image_pull_complete)
      {:error, reason} -> send(state.caller_pid, {:image_pull_error, reason})
    end

    {:stop, :normal, state}
  end

  defp stop_with_stream_error(reason, state) do
    Logger.error("GenServer: Image Pull: stream error: #{inspect(reason)}")
    error = Utils.docker_error({:image_pull, :stream}, reason)
    send(state.caller_pid, {:image_pull_error, error})
    {:stop, :normal, state}
  end

  defp consume_stream(state, body) do
    {stream, events} = ImagePullStream.consume(state.stream, body)

    state
    |> Map.put(:stream, stream)
    |> publish_stream_events(events)
  end

  defp publish_stream_events(state, events) do
    Enum.reduce(events, state, fn
      {:progress, action, current, total}, state ->
        maybe_publish_progress(state, action, current, total)
    end)
  end

  defp maybe_publish_progress(%{job_id: nil} = state, _action, _current, _total), do: state

  defp maybe_publish_progress(state, action, current, total) do
    now = state.clock.()

    if is_nil(state.last_send) or now >= state.last_send + @send_interval do
      format_options = [decimals: 2]
      label = if action == "Downloading", do: "download", else: "extract"
      message = "#{label}: #{Size.human_readable(current, format_options)}/#{Size.human_readable(total, format_options)}"

      Client.send_job_update_message(state.job_id, state.job_name, message, state.dispatcher)
      %{state | last_send: now}
    else
      state
    end
  end
end
