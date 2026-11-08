defmodule Exdock.Server.Logging do
  @moduledoc """
  Maintains user-visible log history and live job status.

  The process subscribes to node and job PubSub events, converts them into
  status/log view models, and broadcasts those models through
  `Exdock.Server.Broadcast`.
  """

  use GenServer
  require Logger
  alias Phoenix.PubSub
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Event
  alias Exdock.Server.Logging.{AppendEntry, Log, Runtime, ServerState, Status}
  alias Exdock.Server.Broadcast
  alias Exdock.Server.Logging.State
  alias Exdock.Server.Notifier

  @event_topics ["nodechange"]

  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    start_options = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, init_opts, start_options)
  end

  @impl true
  def init(opts) do
    state = ServerState.new(Runtime.new(opts))

    case maybe_subscribe_to_event_topics(state, opts) do
      :ok -> {:ok, state}
      {:error, error} -> {:stop, error}
    end
  end

  @doc false
  @spec submit_clear_errors(Ecto.UUID.t(), GenServer.server()) ::
          :ok
          | {:error, {:runtime_unavailable, :not_found | :timeout}}
          | {:error, {:runtime_failure, term()}}
  def submit_clear_errors(operation_id, server \\ __MODULE__) when is_binary(operation_id) do
    GenServer.call(server, {:submit_clear_errors, operation_id})
  catch
    :exit, {:noproc, _call} -> {:error, {:runtime_unavailable, :not_found}}
    :exit, {:timeout, _call} -> {:error, {:runtime_unavailable, :timeout}}
    :exit, reason -> {:error, {:runtime_failure, reason}}
  end

  @doc """
    Adds a new log entry to the log history.

    Entries can be simple messages or job logs.

    Options:
    - `:automated` - If `true`, marks the log as automated (visible to operators but
      not user-created).
    - `:broadcast` - If `true`, the logs will be broadcast after adding the entry.
    - `:hidden` - If `true`, the log entry will not be displayed in the Web UI.
  """
  @spec add_to_log(atom(), any(), String.t() | nil, Keyword.t()) :: :ok
  def add_to_log(message_name, message_data, job_id, opts \\ []) do
    {server, entry_opts} = Keyword.pop(opts, :server, __MODULE__)
    add_to_log(AppendEntry.new(message_name, message_data, job_id, entry_opts), server)
  end

  @doc false
  @spec add_to_log(AppendEntry.t(), GenServer.server()) :: :ok
  def add_to_log(%AppendEntry{} = input, server \\ __MODULE__),
    do: cast(server, {:add_log_entry, input})

  @spec snapshot(GenServer.server()) :: %{revision: non_neg_integer(), status: Status.t(), log: [Log.t()]}
  def snapshot(server \\ __MODULE__) do
    {:ok, snapshot} = GenServer.call(server, :snapshot)
    snapshot
  end

  # -- Handle updates from subscribed topics
  @impl true
  def handle_info(%Event{} = event, %ServerState{} = state),
    do: reduce_event(state, event)

  def handle_info({:nodechange, status, node} = event, %ServerState{} = state)
      when status in [:up, :down] and is_binary(node),
      do: reduce_event(state, event)

  def handle_info({:execute_admitted_clear_errors, operation_id}, %ServerState{runtime: runtime} = state)
      when is_binary(operation_id) do
    {:noreply, state} = reduce_event(state, :clear_errors)
    :ok = runtime.events.operation_finished(operation_id, :clear_errors, %{status: :completed})
    {:noreply, state}
  end

  # -- handlers for cast and call

  # -- log
  @impl true
  def handle_cast({:add_log_entry, %AppendEntry{} = input}, %ServerState{} = state),
    do: reduce_event(state, input)

  @impl true
  def handle_call(:snapshot, _from, %ServerState{domain: domain} = state) do
    snapshot = %{revision: domain.revision, status: domain.job_status, log: Log.current_log(domain)}
    {:reply, {:ok, snapshot}, state}
  end

  @impl true
  def handle_call({:submit_clear_errors, operation_id}, _from, %ServerState{runtime: runtime} = state)
      when is_binary(operation_id) do
    :ok = runtime.events.operation_accepted(operation_id, :clear_errors)
    send(self(), {:execute_admitted_clear_errors, operation_id})
    {:reply, :ok, state}
  end

  # private helpers for cast/call
  defp cast(server, to_cast), do: GenServer.cast(server, to_cast)

  defp maybe_subscribe_to_event_topics(state, opts) do
    if Keyword.get(opts, :subscribe?, true), do: subscribe_to_event_topics(state), else: :ok
  end

  defp subscribe_to_event_topics(%ServerState{runtime: runtime}) do
    with :ok <- Jobs.subscribe(runtime.pubsub) do
      Exdock.Result.each(@event_topics, &PubSub.subscribe(runtime.pubsub, &1, link: true))
    end
  end

  defp reduce_event(%ServerState{domain: domain, runtime: runtime} = state, event) do
    {domain, effects} = State.transition(domain, event, runtime.context_provider.())
    Enum.each(effects, &run_effect(&1, runtime))
    {:noreply, ServerState.put_domain(state, domain)}
  end

  defp run_effect({:broadcast, domain, data, revision}, runtime),
    do: Broadcast.broadcast(runtime.broadcast, domain, data, revision: revision)

  defp run_effect({:logger, level, message}, _runtime),
    do: Logger.log(level, message)

  defp run_effect({:notify_repository_release, release}, runtime),
    do: Notifier.notify_repository_release(release, runtime.notifier)
end
