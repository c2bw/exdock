defmodule Exdock.Server.Jobs.State.Results.Completion do
  @moduledoc """
  Terminal job transition assembled as explicit state and effect phases.

  Result propagation must remain ahead of newly released work, while package,
  continuation, and monitor cleanup effects run after dispatch. Naming those
  phases here keeps that ordering visible and independently testable.
  """

  alias Exdock.Server.Jobs

  alias Exdock.Server.Jobs.State.{
    Continuations,
    Dispatcher,
    Linked,
    Nodes,
    Packages,
    Queue,
    Running
  }

  @enforce_keys [
    :state,
    :linked_result_effects,
    :dispatch_effects,
    :package_effects,
    :continuation_effects,
    :monitor_effects
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          state: map(),
          linked_result_effects: [term()],
          dispatch_effects: [term()],
          package_effects: [term()],
          continuation_effects: [term()],
          monitor_effects: [term()]
        }

  @spec build(map(), Jobs.Result.t()) :: t()
  def build(state, %Jobs.Result{} = result) do
    linked_result_effects = linked_result_effects(state, result)
    {state, dispatch_effects} = dispatch_released_dependents(state, result)

    {state, package_effects, continuation_effects, monitor_effects} =
      clean_terminal_indexes(state, result)

    %__MODULE__{
      state: state,
      linked_result_effects: linked_result_effects,
      dispatch_effects: dispatch_effects,
      package_effects: package_effects,
      continuation_effects: continuation_effects,
      monitor_effects: monitor_effects
    }
  end

  @spec result(t()) :: {map(), [term()]}
  def result(%__MODULE__{} = completion) do
    effects =
      List.flatten([
        completion.linked_result_effects,
        completion.dispatch_effects,
        completion.package_effects,
        completion.continuation_effects,
        completion.monitor_effects
      ])

    {completion.state, effects}
  end

  defp linked_result_effects(%{linked_id: linked_id}, %Jobs.Result{
         id: id,
         node: node,
         data: data,
         error: error
       }) do
    linked_id
    |> Linked.get_linked(id)
    |> Enum.map(fn linked_id ->
      {:job_result, Jobs.Result.new(linked_id, node, data, error)}
    end)
  end

  defp dispatch_released_dependents(state, %Jobs.Result{id: id, error: error}) do
    Dispatcher.run(state, {:finish, id, error})
  end

  defp clean_terminal_indexes(
         %{
           running: running,
           linked_id: linked_id,
           packages: packages,
           queued_jobs: queued_jobs,
           continuations: continuations,
           nodes_jobs: nodes_jobs,
           local_workers: local_workers
         } = state,
         %Jobs.Result{id: id, error: error} = result
       ) do
    {local_workers, monitor_refs} = pop_local_worker_monitors(local_workers, id)
    {packages, package_effects} = Packages.result(packages, result)
    {continuations, continuation_effects} = Continuations.complete(continuations, id, error)

    updated_state = %{
      state
      | running: Running.delete_job(running, id),
        nodes_jobs: Nodes.remove(nodes_jobs, id),
        linked_id: Linked.remove_link(linked_id, id),
        packages: packages,
        queued_jobs: Queue.remove(queued_jobs, id),
        continuations: continuations,
        local_workers: local_workers
    }

    monitor_effects = Enum.map(monitor_refs, &{:demonitor, &1})
    {updated_state, package_effects, continuation_effects, monitor_effects}
  end

  defp pop_local_worker_monitors(local_workers, job_id)
       when is_map(local_workers) and is_binary(job_id) do
    Enum.reduce(local_workers, {%{}, []}, fn
      {monitor_ref, ^job_id}, {remaining_workers, monitor_refs} ->
        {remaining_workers, [monitor_ref | monitor_refs]}

      {monitor_ref, other_job_id}, {remaining_workers, monitor_refs} ->
        {Map.put(remaining_workers, monitor_ref, other_job_id), monitor_refs}
    end)
  end
end
