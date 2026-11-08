defmodule Exdock.Server.State.ClientMessages.ContainerJobs do
  @moduledoc false

  alias Exdock.Protocol.Messages
  alias Exdock.Runtime.Command
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Catalog
  alias Exdock.Server.Jobs.Job
  alias Exdock.Server.Jobs.Result
  alias Exdock.Server.State
  alias Exdock.Server.State.Change.Outcome
  alias Exdock.Server.State.Storage

  @mutating_actions Catalog.container_mutation_names()
  @post_mutation_refresh_delay_ms 50

  @spec reduce(State.t(), Messages.JobResult.t(), DateTime.t()) ::
          Exdock.Server.State.ClientMessages.result()
  def reduce(
        %State{} = state,
        %Messages.JobResult{
          job: %Job{name: action, id: job_id},
          result: %Result{node: node, data: data, error: error}
        },
        %DateTime{}
      )
      when action in @mutating_actions do
    {state, complete_mutating_job(action, job_id, node, data, error)}
  end

  def reduce(
        %State{} = state,
        %Messages.JobResult{
          job: %Job{name: :container_logs, id: job_id},
          result: %Result{
            node: node,
            data: {container_id, logs},
            error: error
          }
        },
        %DateTime{} = occurred_at
      )
      when is_list(logs) do
    {updated_state, change_effects} =
      reduce_change(
        state,
        Storage.Containers.Change.logs(node, container_id, logs, occurred_at)
      )

    effects =
      log_container_logs_error(node, container_id, error) ++
        [job_result(job_id, node, container_id, error)] ++ change_effects

    {updated_state, effects}
  end

  def reduce(
        %State{} = state,
        %Messages.JobResult{
          job: %Job{name: :container_logs, id: job_id},
          result: %Result{node: node, data: data, error: error}
        },
        %DateTime{}
      )
      when not is_nil(error) do
    effects = [
      log(:error, "Error fetching logs on node [#{node}]: #{inspect(error)}"),
      job_result(job_id, node, data, error)
    ]

    {state, effects}
  end

  defp complete_mutating_job(_action, job_id, node, data, nil) do
    [schedule_post_mutation_refresh(node), job_result(job_id, node, data, nil)]
  end

  defp complete_mutating_job(action, job_id, node, data, error) do
    [
      log_mutation_failure(action, node, data, error),
      schedule_post_mutation_refresh(node),
      job_result(job_id, node, data, error)
    ]
  end

  defp schedule_post_mutation_refresh(node) when is_binary(node) do
    {:server_command, Command.Cluster.refresh_node(node, :no), delay: @post_mutation_refresh_delay_ms}
  end

  defp job_result(job_id, node, data, error) do
    {:job_result, Jobs.Result.new(job_id, node, data, error)}
  end

  defp log_container_logs_error(_node, _container_id, nil), do: []

  defp log_container_logs_error(node, container_id, error) do
    [
      log(
        :error,
        "Error fetching logs for [#{container_id}] on node [#{node}]: #{inspect(error)}"
      )
    ]
  end

  defp log_mutation_failure(action, node, subject, error) do
    verb = Catalog.failure_verb!(action)
    log(:error, "Error #{verb} [#{subject}] on node [#{node}]: #{inspect(error)}")
  end

  defp reduce_change(%State{} = state, mutation) do
    case State.Change.reduce(state, mutation) do
      %Outcome{state: updated_state, effects: effects} ->
        {updated_state, effects}

      {:error, reason, unchanged_state} ->
        {unchanged_state, [log(:error, "State mutation rejected: #{inspect(reason)}")]}
    end
  end

  defp log(level, message), do: {:log, level, message}
end
