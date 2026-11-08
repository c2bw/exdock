defmodule Exdock.Server.Logging.State.JobEvents do
  @moduledoc "Job lifecycle transitions for activity state."

  alias Exdock.Server.Jobs.{Event, Info, Job, Message, Result, Update}
  alias Exdock.Server.Logging.{AppendEntry, Context, State, Status}
  alias Exdock.Server.Logging.State.Reducer
  alias Exdock.Server.Logging.Status.Lifecycle

  @spec transition(State.t(), Event.t(), Context.t()) :: {State.t(), [State.effect()]}
  def transition(
        %State{} = state,
        %Event{type: :job_started, job: %Job{name: name, id: id, data: data} = job},
        %Context{} = context
      ) do
    {state, log_effects} = maybe_log_start(state, job, context)
    lifecycle = Lifecycle.started(name, id, Job.locations(job), data, context.now)
    Reducer.update_status(state, &Status.start(&1, lifecycle), log_effects)
  end

  def transition(
        %State{} = state,
        %Event{
          type: :job_finished,
          info: %Info{name: name},
          result: %Result{node: node, id: id, data: nil, error: :nodedown}
        },
        %Context{} = context
      ) do
    warning = "Node disconnected while executing job: #{name} on [#{node}]"
    lifecycle = Lifecycle.finished(name, id, node, nil, "node disconnected", context.now)
    {status, log_update, effects} = Status.result_transition(state.job_status, lifecycle)

    Reducer.apply_status_transition(
      state,
      status,
      log_update,
      [{:logger, :warning, warning} | effects],
      context
    )
  end

  def transition(
        %State{} = state,
        %Event{
          type: :job_finished,
          info: %Info{name: name},
          result: %Result{node: node, id: id, data: result, error: error}
        },
        %Context{} = context
      ) do
    lifecycle = Lifecycle.finished(name, id, node, result, error, context.now)
    {status, log_update, effects} = Status.result_transition(state.job_status, lifecycle)
    Reducer.apply_status_transition(state, status, log_update, effects, context)
  end

  def transition(
        %State{} = state,
        %Event{
          type: :job_updated,
          info: %Info{name: name},
          update: %Update{id: id, node: node, update: update, error: error}
        },
        %Context{} = context
      ) do
    lifecycle = Lifecycle.updated(name, id, node, update, error, context.now)
    {status, log_update, effects} = Status.update_transition(state.job_status, lifecycle)
    Reducer.apply_status_transition(state, status, log_update, effects, context)
  end

  def transition(
        %State{} = state,
        %Event{type: :job_message, message: %Message{id: id, name: name, node: node, message: message}},
        %Context{}
      ) do
    Reducer.update_status(state, &Status.update_job_message(&1, name, id, node, message))
  end

  defp maybe_log_start(
         %State{} = state,
         %Job{name: name, data: data, id: id, is_automated: automated?},
         %Context{} = context
       ) do
    case Status.log(name, data) do
      false ->
        {state, []}

      {data_to_log, log_opts} ->
        Reducer.append_log(
          state,
          AppendEntry.new(name, data_to_log, id,
            automated: automated?,
            hidden: Keyword.get(log_opts, :hidden, false),
            broadcast: Keyword.get(log_opts, :broadcast, true)
          ),
          context
        )
    end
  end
end
