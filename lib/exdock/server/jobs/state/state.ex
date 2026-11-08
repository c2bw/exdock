defmodule Exdock.Server.Jobs.State do
  @moduledoc """
  Pure state transitions for the job dispatcher.

  The dispatcher stores queued details, running jobs, package membership, linked
  duplicate jobs, node ownership, and named workflow continuations. This module decides
  what can start after an event and leaves process communication to
  `Exdock.Server.Jobs`.
  """

  alias Exdock.Server.Jobs

  alias Exdock.Server.Jobs.State.{
    Continuations,
    Dispatcher,
    Executions,
    Linked,
    Nodes,
    Packages,
    Queue,
    Results,
    Running
  }

  defstruct [
    :running,
    :nodes_jobs,
    :queued_jobs,
    :linked_id,
    :packages,
    :continuations,
    local_workers: %{},
    remote_errors: %{},
    executions: nil
  ]

  @type t :: %__MODULE__{
          running: Running.t(),
          nodes_jobs: Nodes.t(),
          queued_jobs: Queue.t(),
          linked_id: Linked.t(),
          packages: Packages.t(),
          continuations: Continuations.t(),
          local_workers: %{optional(reference()) => String.t()},
          remote_errors: %{optional(String.t()) => Jobs.Result.t()},
          executions: Executions.t()
        }

  @spec new() :: t()
  def new do
    # Each sub-structure owns one index over the same job lifecycle. Keeping them
    # separate makes queue selection, node cleanup, package completion, and
    # duplicate linking independent.
    %__MODULE__{
      running: Running.new(),
      nodes_jobs: Nodes.new(),
      queued_jobs: Queue.new(),
      linked_id: Linked.new(),
      packages: Packages.new(),
      continuations: Continuations.new(),
      executions: Executions.new(),
      local_workers: %{}
    }
  end

  @type event ::
          {:add, Jobs.Detail.t() | list(Jobs.Detail.t()) | Jobs.Package.t()}
          | {:update, Jobs.Update.t()}
          | {:result, Jobs.Result.t()}
          | {:run, Jobs.Detail.start_event()}

  @type effect ::
          {:job_started, Jobs.Job.t()}
          | {:job_result, Jobs.Result.t()}
          | {:job_finished, Jobs.Info.t(), Jobs.Result.t()}
          | {:start_local, String.t(), (String.t() -> term())}
          | {:start_remote, String.t(), Jobs.Job.t()}
          | {:demonitor, reference()}
          | Packages.effect()
          | Continuations.effect()

  @spec transition(t(), event()) :: {t(), [effect()]}
  def transition(%__MODULE__{} = state, {:add, work}),
    do: state |> add(work) |> Dispatcher.run()

  def transition(%__MODULE__{} = state, {:update, %Jobs.Update{} = update}), do: Results.update(state, update)

  def transition(%__MODULE__{} = state, {:result, %Jobs.Result{} = result}),
    do: Results.handle(state, result)

  def transition(%__MODULE__{} = state, {:run, event}), do: Dispatcher.run(state, event)

  @doc """
  Return cross-index consistency errors for dispatcher state.

  Secondary node/link/worker indexes may only reference currently running jobs.
  """
  @spec invariant_errors(t()) :: [term()]
  def invariant_errors(
        %__MODULE__{
          running: running,
          nodes_jobs: %Nodes{nodes: nodes},
          linked_id: %Linked{linked: linked},
          local_workers: local_workers,
          executions: executions
        } = _state
      ) do
    running_ids = Running.ids(running)

    []
    |> maybe_add_invariant_error(:node_index, indexed_node_job_ids(nodes), running_ids)
    |> maybe_add_invariant_error(:link_index, Map.keys(linked), running_ids)
    |> maybe_add_invariant_error(:local_worker_index, Map.values(local_workers), running_ids)
    |> maybe_add_invariant_error(:execution_index, Map.keys(executions.parents), running_ids)
    |> Enum.reverse()
  end

  @doc """
  Add work to the queue.

  Packages are registered first, then their details are queued so package-level
  completion can be updated as each detail result arrives.
  """
  @spec add(t(), Jobs.Detail.t() | list(Jobs.Detail.t()) | Jobs.Package.t()) :: t()
  def add(%__MODULE__{queued_jobs: queued_jobs} = state, %Jobs.Detail{} = detail) do
    %{state | queued_jobs: Queue.enqueue(queued_jobs, detail)}
  end

  def add(%__MODULE__{packages: packages} = state, %Jobs.Package{details: details} = package) do
    state = %{state | packages: Packages.add(packages, package)}
    add(state, details)
  end

  def add(%__MODULE__{} = state, details) when is_list(details) do
    Enum.reduce(details, state, &enqueue_detail/2)
  end

  @spec get_job_info(t(), String.t()) :: Jobs.Info.t() | nil
  def get_job_info(%__MODULE__{running: running, executions: executions}, id) when is_binary(id) do
    running
    |> Running.get(id)
    |> case do
      nil -> Executions.info(executions, id)
      job -> Jobs.Info.new(job)
    end
  end

  @doc false
  @spec local_worker_down(t(), reference()) :: {:ok, String.t(), t()} | :unknown
  def local_worker_down(%__MODULE__{local_workers: local_workers} = state, monitor_ref)
      when is_reference(monitor_ref) do
    case Map.pop(local_workers, monitor_ref) do
      {nil, _local_workers} -> :unknown
      {job_id, local_workers} -> {:ok, job_id, %{state | local_workers: local_workers}}
    end
  end

  @doc false
  @spec track_local_worker(t(), reference(), String.t()) :: t()
  def track_local_worker(%__MODULE__{local_workers: local_workers} = state, monitor_ref, job_id)
      when is_reference(monitor_ref) and is_binary(job_id) do
    %{state | local_workers: Map.put(local_workers, monitor_ref, job_id)}
  end

  defp enqueue_detail(%Jobs.Detail{} = detail, %__MODULE__{} = state), do: add(state, detail)

  defp indexed_node_job_ids(nodes) do
    nodes
    |> Map.values()
    |> Enum.reduce(MapSet.new(), &MapSet.union(&2, &1))
  end

  defp maybe_add_invariant_error(errors, index, referenced_ids, running_ids) do
    unknown_ids =
      referenced_ids
      |> MapSet.new()
      |> MapSet.difference(running_ids)
      |> MapSet.to_list()

    if unknown_ids == [], do: errors, else: [{index, unknown_ids} | errors]
  end
end
