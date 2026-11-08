defmodule Exdock.Server.State.Change.Outcome do
  @moduledoc """
  Named result of a successful state-change plan.

  Plans attach broadcast options to their direct-domain result. Resolution
  replaces those options with the complete effect list while preserving any
  operation-specific result for callers that requested it.
  """

  alias Exdock.Server.State
  alias Exdock.Server.State.Effects

  @enforce_keys [:state, :effects]
  defstruct [:state, :operation_result, broadcast_opts: [], effects: []]

  @type t :: %__MODULE__{
          state: State.t(),
          broadcast_opts: keyword(),
          effects: [Effects.effect()],
          operation_result: map() | nil
        }

  @spec new(State.t(), [Effects.effect()], map() | nil) :: t()
  def new(%State{} = state, effects, operation_result \\ nil)
      when is_list(effects) and (is_map(operation_result) or is_nil(operation_result)) do
    %__MODULE__{state: state, effects: effects, operation_result: operation_result}
  end

  @spec planned(State.t(), keyword(), [Effects.effect()], map() | nil) :: t()
  def planned(%State{} = state, broadcast_opts, effects, operation_result \\ nil)
      when is_list(broadcast_opts) and is_list(effects) and
             (is_map(operation_result) or is_nil(operation_result)) do
    %__MODULE__{
      state: state,
      broadcast_opts: broadcast_opts,
      effects: effects,
      operation_result: operation_result
    }
  end

  @spec resolved(t(), State.t(), [Effects.effect()]) :: t()
  def resolved(%__MODULE__{} = outcome, %State{} = state, effects) when is_list(effects) do
    %{outcome | state: state, broadcast_opts: [], effects: effects}
  end
end
