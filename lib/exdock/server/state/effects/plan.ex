defmodule Exdock.Server.State.Effects.Plan do
  @moduledoc """
  Ordered phases emitted by an authoritative state transition.

  Producers name the purpose of each effect batch instead of relying on a
  chain of list concatenations. The interpreter still receives a flat list,
  but the ordering contract is centralized here.
  """

  alias Exdock.Server.State.Effects

  @enforce_keys []
  defstruct before_publication: [],
            status_changes: [],
            publications: [],
            derived_publications: [],
            follow_ups: [],
            cleanup: []

  @type t :: %__MODULE__{
          before_publication: [Effects.effect()],
          status_changes: [Effects.effect()],
          publications: [Effects.effect()],
          derived_publications: [Effects.effect()],
          follow_ups: [Effects.effect()],
          cleanup: [Effects.effect()]
        }

  @spec new(keyword([Effects.effect()])) :: t()
  def new(phases \\ []) when is_list(phases) do
    phases
    |> then(&struct!(__MODULE__, &1))
    |> validate!()
  end

  @spec effects(t()) :: [Effects.effect()]
  def effects(%__MODULE__{} = plan) do
    List.flatten([
      plan.before_publication,
      plan.status_changes,
      plan.publications,
      plan.derived_publications,
      plan.follow_ups,
      plan.cleanup
    ])
  end

  defp validate!(%__MODULE__{} = plan) do
    plan
    |> Map.from_struct()
    |> Enum.each(fn {phase, effects} ->
      unless is_list(effects) do
        raise ArgumentError, "effect phase #{phase} must be a list"
      end
    end)

    plan
  end
end
