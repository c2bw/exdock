defmodule Exdock.Runtime.Command.Executor do
  @moduledoc """
  Interprets normalized command outcomes for the authoritative runtime.

  The coordinator owns the state and mailbox; this module owns the policy for
  enqueueing work and publishing terminal operation events.
  """

  alias Exdock.Events
  alias Exdock.Runtime.Command
  alias Exdock.Runtime.Command.Execution
  alias Exdock.Server.Jobs.Plan
  alias Exdock.Server.Jobs.Submission
  alias Exdock.Server.State

  @spec execute(State.t(), Ecto.UUID.t() | nil, Command.internal_t(), keyword()) :: State.t()
  def execute(%State{} = state, operation_id, command, opts)
      when (is_binary(operation_id) or is_nil(operation_id)) and is_list(opts) do
    {updated_state, effects} =
      Execution.resolve(state, Command.execute(state, command), operation_id, command, opts)

    Enum.each(effects, &run_effect/1)
    updated_state
  end

  defp run_effect({:submit_plan, %Plan{} = plan}), do: Submission.submit(plan)

  defp run_effect({:finish_operation, operation_id, kind, result}),
    do: Events.operation_finished(operation_id, kind, result)
end
