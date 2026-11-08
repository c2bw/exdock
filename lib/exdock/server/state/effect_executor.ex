defmodule Exdock.Server.State.EffectExecutor do
  @moduledoc """
  Resolves and invokes the configured interpreter for committed state effects.

  Effect data remains independent of server state; this module owns the runtime
  dependency on both the state snapshot and its configured interpreter.
  """

  alias Exdock.Server.State
  alias Exdock.Server.State.Effects

  @spec run(State.t(), [Effects.effect()]) :: :ok
  def run(%State{} = state, effects) when is_list(effects) do
    runner = Application.fetch_env!(:exdock, :state_effect_runner)
    run(state, effects, runner)
  end

  @spec run(State.t(), [Effects.effect()], module() | (State.t(), [Effects.effect()] -> :ok)) :: :ok
  def run(%State{} = state, effects, runner) when is_list(effects) and is_atom(runner),
    do: runner.run(state, effects)

  def run(%State{} = state, effects, runner)
      when is_list(effects) and is_function(runner, 2),
      do: runner.(state, effects)
end
