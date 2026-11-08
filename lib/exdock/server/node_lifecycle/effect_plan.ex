defmodule Exdock.Server.NodeLifecycle.EffectPlan do
  @moduledoc """
  Ordered external effects for a node lifecycle decision.

  State transition effects are interpreted before lifecycle publications, and
  follow-up commands are always dispatched last.
  """

  @enforce_keys []
  defstruct diagnostics: [], state_transition: [], publications: [], commands: []

  @type t :: %__MODULE__{
          diagnostics: [term()],
          state_transition: [term()],
          publications: [term()],
          commands: [term()]
        }

  @spec new(keyword([term()])) :: t()
  def new(phases \\ []) when is_list(phases), do: struct!(__MODULE__, phases)

  @spec effects(t()) :: [term()]
  def effects(%__MODULE__{} = plan) do
    List.flatten([
      plan.diagnostics,
      plan.state_transition,
      plan.publications,
      plan.commands
    ])
  end
end
