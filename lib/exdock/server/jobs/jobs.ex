defmodule Exdock.Server.Jobs do
  @moduledoc """
  Runtime job dispatcher for local work and remote client work.

  This GenServer owns the job queue/running state, publishes job lifecycle events
  over PubSub, and marks jobs as failed when their target node disconnects.
  """

  use GenServer
  require Logger
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.{EffectRunner, Publisher, Runtime, ServerState}

  # Runtime boundary: this module owns job state updates and PubSub fanout.
  # Public API functions only dispatch to the GenServer; callbacks are the
  # single writer to shared job state.

  def start_link(args) when is_list(args) do
    {name, init_args} = Keyword.pop(args, :name, __MODULE__)
    start_options = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, init_args, start_options)
  end

  @impl true
  def init(args) do
    runtime = Runtime.new(args)

    with :ok <- runtime.publisher.subscribe_to_node_changes(runtime.pubsub) do
      {:ok, ServerState.new(runtime)}
    else
      {:error, error} -> {:stop, error}
    end
  end

  @impl true
  def handle_cast({:add_job, job_format}, %ServerState{domain: domain, runtime: runtime} = state) do
    runtime.publisher.package_started(job_format, Runtime.publisher_opts(runtime))
    {:noreply, ServerState.put_domain(state, add_queued_work(domain, job_format, runtime))}
  end

  @impl true
  def handle_cast({:job_result, %Jobs.Result{} = result}, %ServerState{domain: domain, runtime: runtime} = state) do
    {:noreply, ServerState.put_domain(state, EffectRunner.process_result(domain, result, runtime))}
  end

  @impl true
  def handle_cast(
        {:job_update, %Jobs.Update{id: id} = update},
        %ServerState{domain: domain, runtime: runtime} = state
      ) do
    # Updates are progress events; they may also remove a node from the set of
    # remote targets still expected to answer.
    runtime.publisher.running_job_event(
      domain,
      :job_update,
      id,
      update,
      Runtime.publisher_opts(runtime)
    )

    {:noreply, ServerState.put_domain(state, apply_job_update(domain, update, runtime))}
  end

  @impl true
  def handle_cast({:job_info_message, %Jobs.Message{} = message}, %ServerState{runtime: runtime} = state) do
    :ok = runtime.publisher.job_message(message, Runtime.publisher_opts(runtime))
    {:noreply, state}
  end

  # Node lifecycle changes can drive job cleanup. On disconnect, we convert the
  # loss of reachability into synthetic job results so existing completion paths
  # stay consistent.
  @impl true
  def handle_info({:nodechange, :up, _node}, %ServerState{} = state), do: {:noreply, state}

  def handle_info(
        {:nodechange, :down, node},
        %ServerState{domain: %Jobs.State{nodes_jobs: nodes}} = state
      ) do
    # Convert disconnects into ordinary job results so package and chained-job
    # cleanup paths run exactly as they do for client-reported failures.
    nodes
    |> Jobs.State.Nodes.ids(node)
    |> broadcast_node_down_results(node, self())

    {:noreply, state}
  end

  def handle_info(
        {:DOWN, monitor_ref, :process, _pid, reason},
        %ServerState{domain: domain, runtime: runtime} = state
      ) do
    case Jobs.State.local_worker_down(domain, monitor_ref) do
      {:ok, job_id, domain} ->
        Logger.error("Local job #{job_id} worker exited before reporting a result: #{inspect(reason)}")
        result = Jobs.Result.new(job_id, nil, nil, {:local_job_failed, :exit, reason})
        {:noreply, ServerState.put_domain(state, EffectRunner.process_result(domain, result, runtime))}

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:local_job_failure, %Jobs.Result{} = result},
        %ServerState{domain: domain, runtime: runtime} = state
      ) do
    {:noreply, ServerState.put_domain(state, EffectRunner.process_result(domain, result, runtime))}
  end

  # Public job API:
  # Consumers enqueue work and report progress/results through these narrow
  # helper functions. They intentionally do not apply state directly.

  @doc """
    Record the final result for a running job.

    Results are broadcast to subscribers and then applied to the job state,
    potentially unblocking queued jobs that depend on this one finishing.
  """
  @spec job_result(Jobs.Result.t(), GenServer.server()) :: :ok
  def job_result(%Jobs.Result{} = result, server \\ __MODULE__),
    do: cast(server, {:job_result, result})

  @doc """
    Publish and apply an in-flight job update.

    Remote jobs use updates for progress messages and for marking one target node
    as complete while other nodes continue running.
  """
  @spec job_update(Jobs.Update.t(), GenServer.server()) :: :ok
  def job_update(%Jobs.Update{} = update, server \\ __MODULE__),
    do: cast(server, {:job_update, update})

  @doc """
    Publish an informational job message without changing queue state.
  """
  @spec info_message(Jobs.Message.t(), GenServer.server()) :: :ok
  def info_message(%Jobs.Message{} = message, server \\ __MODULE__),
    do: cast(server, {:job_info_message, message})

  @doc """
    Add a detail, detail list, or package to the queue and attempt to run any
    jobs whose start trigger is currently satisfied.
  """
  @spec add(Jobs.Detail.t() | list(Jobs.Detail.t()) | Jobs.Package.t(), GenServer.server()) :: :ok
  def add(job_format, server \\ __MODULE__), do: cast(server, {:add_job, job_format})

  @doc "Subscribe the calling process to typed job lifecycle events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe(pubsub \\ Exdock.PubSub), do: Publisher.subscribe(pubsub)

  defp add_queued_work(%Jobs.State{} = state, job_format, %Runtime{} = runtime) do
    # Incoming details/packages are normalized inside Jobs.State. After enqueue,
    # the state layer drains runnable details and returns execution effects.
    EffectRunner.transition(state, {:add, job_format}, runtime)
  end

  defp apply_job_update(%Jobs.State{} = state, %Jobs.Update{} = update, %Runtime{} = runtime) do
    EffectRunner.transition(state, {:update, update}, runtime)
  end

  defp broadcast_node_down_results(job_ids, node, server)
       when is_list(job_ids) and is_binary(node) do
    Enum.each(job_ids, &broadcast_node_down_result(&1, node, server))
  end

  defp broadcast_node_down_result(id, node, server)
       when is_binary(id) and is_binary(node) do
    id
    |> Jobs.Result.new(node, nil, :nodedown)
    |> job_result(server)
  end

  # Dispatcher helper keeps all outbound GenServer messages in one place.
  defp cast(server, msg), do: GenServer.cast(server, msg)
end
