defmodule Exdock.Server.Jobs.State.Dispatcher do
  @moduledoc false

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.State.{Continuations, Executions, Gatekeeper, Linked, Nodes, Queue, Running}

  @spec run(map(), Jobs.Detail.start_event()) :: {map(), [term()]}
  def run(%{queued_jobs: queued_jobs} = state, event \\ :instant) do
    {queued_jobs, runnable_details} = Queue.drain_runnable_for(queued_jobs, event)
    state = %{state | queued_jobs: queued_jobs}

    {state, effect_chunks} =
      Enum.reduce(runnable_details, {state, []}, fn detail, {current_state, effect_chunks} ->
        {current_state, detail_effects} = execute_detail(current_state, detail)
        {current_state, [detail_effects | effect_chunks]}
      end)

    effects =
      effect_chunks
      |> Enum.reverse()
      |> List.flatten()

    {state, effects}
  end

  defp execute_detail(
         %{continuations: continuations} = state,
         %Jobs.Detail{id: id, continuation: continuation, spec_list: spec_list} = detail
       ) do
    state = %{state | continuations: Continuations.add(continuations, id, continuation)}

    state = %{state | executions: Executions.add(state.executions, detail)}

    {state, effect_chunks} =
      Enum.reduce(spec_list, {state, []}, fn
        {%Jobs.Spec{} = spec, execution_id}, {acc, effect_chunks} ->
          {acc, spec_effects} = execute_spec(acc, %{detail | id: execution_id}, spec)
          {acc, [spec_effects | effect_chunks]}
      end)

    effects =
      effect_chunks
      |> Enum.reverse()
      |> List.flatten()

    effects =
      case spec_list do
        [{spec, _} | [_ | _]] -> [{:job_started, Jobs.Job.new(detail, spec)} | effects]
        [_single] -> effects
      end

    {state, effects}
  end

  defp execute_spec(state, %Jobs.Detail{} = detail, %Jobs.Spec{} = spec) do
    job =
      detail
      |> Jobs.Job.new(spec)
      |> prepare_dispatch_job(state)

    state =
      state
      |> link_duplicate_job(job)
      |> index_running_job(job)

    {state, dispatch_effects(job)}
  end

  defp prepare_dispatch_job(%Jobs.Job{} = job, state) do
    state.running
    |> Gatekeeper.job(job)
    |> Jobs.Job.set_running()
  end

  defp link_duplicate_job(
         %{running: running, linked_id: linked_id} = state,
         %Jobs.Job{
           id: id,
           status: :linked
         } = job
       ) do
    linked_id = Linked.add(linked_id, id, Running.find_job_id(running, job))
    %{state | linked_id: linked_id}
  end

  defp link_duplicate_job(state, _job), do: state

  defp index_running_job(%{running: running, nodes_jobs: nodes_jobs} = state, %Jobs.Job{} = job) do
    %{
      state
      | running: Running.add(running, job),
        nodes_jobs: Nodes.add(nodes_jobs, job)
    }
  end

  defp dispatch_effects(%Jobs.Job{status: status} = job) when status != :running,
    do: [{:job_started, job}]

  defp dispatch_effects(%Jobs.Job{type: %Jobs.Job.Local{function: function}, id: id} = job),
    do: [{:job_started, job}, {:start_local, id, function}]

  defp dispatch_effects(%Jobs.Job{type: %Jobs.Job.Remote{nodes: nodes}} = job),
    do: [{:job_started, job} | Enum.map(nodes, &{:start_remote, &1, job})]
end
