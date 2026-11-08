defmodule Exdock.Server.Jobs.State.Results do
  @moduledoc false

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.State.Results.Completion
  alias Exdock.Server.Jobs.State.{Executions, Nodes, Running}

  @spec handle(map(), Jobs.Result.t()) :: {map(), [term()]}
  def handle(state, %Jobs.Result{} = result) do
    case record_response(state, result) do
      {:pending, state} ->
        {state, []}

      {:complete, state, result, job} ->
        {state, effects} = state |> Completion.build(result) |> Completion.result()
        {executions, aggregate} = Executions.complete(state.executions, result)
        state = %{state | executions: executions}
        effects = [{:job_finished, Jobs.Info.new(job), result} | effects]

        case aggregate do
          nil ->
            {state, effects}

          {info, parent_result} ->
            {state, parent_effects} = state |> Completion.build(parent_result) |> Completion.result()
            {state, effects ++ [{:job_finished, info, parent_result} | parent_effects]}
        end
    end
  end

  @spec update(map(), Jobs.Update.t()) :: {map(), [term()]}
  def update(state, %Jobs.Update{remove_node: true, id: id, node: node, error: error}) do
    case Running.get_remote(state.running, id) do
      %Jobs.Job{status: :running} ->
        error = if error != nil, do: :error
        handle(state, Jobs.Result.new(id, node, nil, error))

      _unknown_or_linked ->
        {state, []}
    end
  end

  def update(state, %Jobs.Update{}), do: {state, []}

  defp record_response(state, %Jobs.Result{id: id} = result) do
    case Running.get(state.running, id) do
      nil ->
        {:pending, state}

      %Jobs.Job{type: %Jobs.Job.Local{}} = job ->
        {:complete, state, result, job}

      %Jobs.Job{status: :linked} = job ->
        {:complete, state, result, job}

      %Jobs.Job{type: %Jobs.Job.Remote{nodes: nodes}} = job ->
        if result.node in nodes,
          do: record_remote_response(state, result, job),
          else: {:pending, state}
    end
  end

  defp record_remote_response(state, %Jobs.Result{id: id, error: error} = result, job) do
    failure = Map.get(state.remote_errors, id) || if(error != nil, do: result)
    running = Running.remove_node(state.running, id, result.node)
    %Jobs.Job{type: %Jobs.Job.Remote{nodes: remaining_nodes}} = remaining_job = Running.get(running, id)
    nodes_jobs = state.nodes_jobs |> Nodes.remove(id) |> Nodes.add(remaining_job)
    state = %{state | running: running, nodes_jobs: nodes_jobs}

    if remaining_nodes == [] do
      state = %{state | remote_errors: Map.delete(state.remote_errors, id)}
      {:complete, state, failure || result, job}
    else
      errors = if failure == nil, do: state.remote_errors, else: Map.put(state.remote_errors, id, failure)
      {:pending, %{state | remote_errors: errors}}
    end
  end
end
