defmodule Exdock.Server.Automation do
  @moduledoc """
  Plans and applies periodic automation work for the server runtime.
  """

  alias Exdock.Server.Automation.{Handler, Policy}
  alias Exdock.Server.State

  @spec run(State.t(), Ecto.UUID.t() | nil, module()) :: State.t()
  def run(%State{} = state, operation_id, handler \\ Handler)
      when (is_binary(operation_id) or is_nil(operation_id)) and is_atom(handler) do
    {state, effects} = Policy.run(state, operation_id)
    :ok = handler.run(effects)
    state
  end

  @spec change_schedule(State.t(), String.t()) :: State.t()
  def change_schedule(%State{periodic_job: current_job} = state, cron)
      when is_binary(cron) do
    case Policy.change_schedule(%{state | periodic_job: current_job}, cron) do
      {:commit, state, mutation} -> State.Change.change(state, mutation)
      {:reject, state} -> state
    end
  end
end
