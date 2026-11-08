defmodule Exdock.Server.Logging.State do
  @moduledoc """
  Pure reducer state and routing boundary for activity and job-status events.

  Event-family reducers own job, package, and node lifecycle rules. This module
  retains the shared state contract and routes normalized inputs explicitly.
  """

  alias Exdock.Server.Jobs.Event
  alias Exdock.Server.Logging.{AppendEntry, Context, Log, Status}
  alias Exdock.Server.Logging.State.{JobEvents, NodeEvents, PackageEvents, Reducer}

  defstruct revision: 0, job_status: nil, logs: []

  @type t :: %__MODULE__{
          revision: non_neg_integer(),
          job_status: Status.t(),
          logs: [Log.t()]
        }

  @type effect ::
          {:broadcast, :log | :status, term(), non_neg_integer()}
          | {:logger, :warning, String.t()}
          | Status.effect()

  @type event ::
          Event.t()
          | {:nodechange, :up | :down, Exdock.NodeId.t()}
          | AppendEntry.t()
          | {:update_log, String.t(), Log.job_status(), keyword()}
          | :clear_errors

  @spec new() :: t()
  def new, do: %__MODULE__{job_status: Status.new()}

  @spec transition(t(), event(), Context.t()) :: {t(), [effect()]}
  def transition(%__MODULE__{} = state, %Event{type: type} = event, %Context{} = context)
      when type in [:job_started, :job_finished, :job_updated, :job_message],
      do: JobEvents.transition(state, event, context)

  def transition(%__MODULE__{} = state, %Event{type: type} = event, %Context{} = context)
      when type in [:package_started, :package_finished],
      do: PackageEvents.transition(state, event, context)

  def transition(%__MODULE__{} = state, {:nodechange, status, node}, %Context{} = context),
    do: NodeEvents.transition(state, status, node, context)

  def transition(%__MODULE__{} = state, %AppendEntry{} = input, %Context{} = context),
    do: Reducer.append_log(state, input, context)

  def transition(%__MODULE__{} = state, {:update_log, job_id, status, opts}, %Context{} = context),
    do: Reducer.update_logs(state, &Log.update_entry(&1, job_id, status, context.now, opts))

  def transition(%__MODULE__{} = state, :clear_errors, %Context{}),
    do: Reducer.update_status(state, &Status.clear_errors/1)
end
