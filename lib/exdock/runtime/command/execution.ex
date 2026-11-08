defmodule Exdock.Runtime.Command.Execution do
  @moduledoc """
  Pure command-outcome policy for the authoritative runtime.

  Command handlers decide whether work, updated state, or an error was produced.
  This module turns that outcome into explicit effects while the executor remains
  the process-facing interpreter.
  """

  alias Exdock.Runtime.Command
  alias Exdock.Server.Jobs.Plan
  alias Exdock.Server.State

  @type effect ::
          {:submit_plan, Plan.t()}
          | {:finish_operation, Ecto.UUID.t(), atom(), map()}

  @spec resolve(
          State.t(),
          Command.effect(),
          Ecto.UUID.t() | nil,
          Command.internal_t(),
          keyword()
        ) :: {State.t(), [effect()]}
  def resolve(%State{} = state, outcome, operation_id, command, opts)
      when (is_binary(operation_id) or is_nil(operation_id)) and is_list(opts) do
    kind = Keyword.get(opts, :operation_kind, Command.kind(command))

    case outcome do
      {:work, %Plan{} = plan} ->
        resolve_plan(state, plan, operation_id, kind, opts)

      {:state, %State{} = updated_state} ->
        {updated_state, finish_effect(operation_id, kind, %{status: :completed})}

      {:state, %State{} = updated_state, operation_result} when is_map(operation_result) ->
        {updated_state, finish_effect(operation_id, kind, operation_result)}

      {:error, reason} ->
        {state, finish_effect(operation_id, kind, %{error: reason})}
    end
  end

  defp resolve_plan(state, plan, operation_id, kind, opts) do
    plan =
      plan
      |> Plan.attach_operation(operation_id)
      |> Plan.automated(Keyword.get(opts, :automated, plan.automated?))

    if Plan.empty?(plan) do
      {state, finish_effect(operation_id, kind, %{status: :noop})}
    else
      {state, [{:submit_plan, plan}]}
    end
  end

  defp finish_effect(nil, _kind, _result), do: []

  defp finish_effect(operation_id, kind, result)
       when is_binary(operation_id) and is_atom(kind),
       do: [{:finish_operation, operation_id, kind, result}]
end
