defmodule Exdock.Server.State.Change do
  @moduledoc """
  Coordinates authoritative state transitions.

  A transition first reduces the requested domain mutation and reloads derived
  domains. Side effects are returned separately and executed only after the new
  state has been fully assembled.
  """

  alias Exdock.Runtime.Mutation
  alias Exdock.Server.State
  alias Exdock.Server.State.{ContainerStatus, Domain, Effects, Transition}
  alias Exdock.Server.State.Change.{Outcome, Plan, Prepared}
  alias Exdock.Server.State.Effects.Plan, as: EffectPlan

  @type effect :: Effects.effect()
  @type result :: Outcome.t() | {:error, term(), State.t()}
  @type commit_result :: {:ok, State.t()} | {:error, term(), State.t()}
  @type commit_with_result ::
          {:ok, State.t(), map()} | {:error, term(), State.t()}

  @doc false
  def new, do: :stateless

  @spec prepare(State.t(), Mutation.t()) :: Prepared.t()
  def prepare(%State{} = state, %Mutation{domain: domain, action: action} = mutation) do
    %Prepared{
      previous_state: state,
      domain: domain,
      action: action,
      plan: Domain.plan(domain, state, mutation)
    }
  end

  @spec reduce(State.t(), Mutation.t()) :: result()
  def reduce(%State{} = state, %Mutation{} = mutation) do
    state
    |> prepare(mutation)
    |> resolve(&Plan.reduce/1)
  end

  defp resolve(
         %Prepared{previous_state: state, domain: domain, action: action, plan: plan},
         plan_executor
       ) do
    case plan_executor.(plan) do
      {:error, reason} ->
        {:error, reason, state}

      %Outcome{} = outcome ->
        resolve_changed_state(outcome, state, domain, action)
    end
  end

  defp resolve_changed_state(
         %Outcome{
           state: changed_state,
           broadcast_opts: broadcast_opts,
           effects: domain_effects
         } = outcome,
         previous_state,
         domain,
         action
       ) do
    dependents = Domain.dependents(domain, action)

    reloaded_state =
      Enum.reduce(dependents, changed_state, fn dependent, current_state ->
        Domain.reload(dependent, current_state, domain)
      end)

    changed_domains = [domain | dependents]

    effects =
      EffectPlan.new(
        before_publication: domain_effects,
        status_changes: container_status_effects(previous_state, reloaded_state, domain, dependents),
        publications: [
          {:broadcast, domain, broadcast_opts}
          | Enum.map(dependents, &{:broadcast, &1, nil})
        ],
        derived_publications: Effects.derived_broadcasts(changed_domains),
        follow_ups: scheduler_effects(previous_state, reloaded_state)
      )
      |> EffectPlan.effects()

    state = State.bump_revision(reloaded_state)

    Outcome.resolved(outcome, state, effects)
  end

  @spec commit(State.t(), Mutation.t()) :: commit_result()
  def commit(%State{} = state, %Mutation{} = mutation) do
    state
    |> prepare(mutation)
    |> resolve(&Plan.execute/1)
    |> Transition.commit(log_error: true, error_prefix: "State mutation rejected")
  end

  @spec commit_with_result(State.t(), Mutation.t()) :: commit_with_result()
  def commit_with_result(%State{} = state, %Mutation{} = mutation) do
    state
    |> prepare(mutation)
    |> resolve(&Plan.execute/1)
    |> Transition.commit_with_result(log_error: true, error_prefix: "State mutation rejected")
  end

  @spec change(State.t(), Mutation.t()) :: State.t()
  def change(%State{} = state, %Mutation{} = mutation) do
    case commit(state, mutation) do
      {:ok, updated_state} -> updated_state
      {:error, _reason, unchanged_state} -> unchanged_state
    end
  end

  defp scheduler_effects(
         %State{periodic_job: %State.PeriodicJob{cron_string: old_cron}},
         %State{periodic_job: %State.PeriodicJob{cron_string: new_cron} = job}
       )
       when old_cron != new_cron,
       do: [{:schedule_automation, job}]

  defp scheduler_effects(_old_state, _new_state), do: []

  defp container_status_effects(before_state, after_state, domain, dependents) do
    if :containers in [domain | dependents] do
      before_state
      |> ContainerStatus.transitions(after_state)
      |> Enum.map(&{:container_status, &1})
    else
      []
    end
  end
end
