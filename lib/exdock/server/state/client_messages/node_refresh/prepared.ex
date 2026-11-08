defmodule Exdock.Server.State.ClientMessages.NodeRefresh.Prepared do
  @moduledoc """
  Pure node-refresh decision awaiting its durable snapshot commit.

  Keeping both outcomes in the value lets the commit boundary publish the new
  projection only after persistence succeeds.
  """

  alias Exdock.Server.State
  alias Exdock.Server.State.Effects
  alias Exdock.Server.State.Effects.Plan, as: EffectPlan
  alias Exdock.Server.State.Storage.Cluster.SnapshotCommit

  @enforce_keys [:previous_state, :updated_state, :snapshot_commit, :success_effects, :failure_effects]
  defstruct [:previous_state, :updated_state, :snapshot_commit, :success_effects, :failure_effects]

  @type t :: %__MODULE__{
          previous_state: State.t(),
          updated_state: State.t(),
          snapshot_commit: SnapshotCommit.t() | nil,
          success_effects: [Effects.effect()],
          failure_effects: (term() -> [Effects.effect()])
        }

  @spec immediate(State.t(), [Effects.effect()]) :: t()
  def immediate(%State{} = state, effects) when is_list(effects) do
    %__MODULE__{
      previous_state: state,
      updated_state: state,
      snapshot_commit: nil,
      success_effects: effects,
      failure_effects: fn _reason -> effects end
    }
  end

  @spec persisted(
          State.t(),
          State.t(),
          SnapshotCommit.t(),
          [Effects.effect()],
          [Effects.effect()],
          term(),
          String.t()
        ) :: t()
  def persisted(
        %State{} = previous_state,
        %State{} = updated_state,
        %SnapshotCommit{} = snapshot_commit,
        success_effects,
        refresh_log_effects,
        job_id,
        node
      ) do
    %__MODULE__{
      previous_state: previous_state,
      updated_state: updated_state,
      snapshot_commit: snapshot_commit,
      success_effects: success_effects,
      failure_effects: fn reason ->
        EffectPlan.new(
          before_publication: refresh_log_effects,
          follow_ups: [
            {:log, :error, "Failed to persist node refresh for [#{node}]: #{inspect(reason)}"},
            {:job_update,
             Exdock.Server.Jobs.Update.new(
               job_id,
               node,
               %{},
               true,
               {:persistence_failed, reason}
             )}
          ]
        )
        |> EffectPlan.effects()
      end
    }
  end

  @spec execute(t()) :: {State.t(), [Effects.effect()]}
  def execute(%__MODULE__{snapshot_commit: nil} = prepared),
    do: {prepared.updated_state, prepared.success_effects}

  def execute(%__MODULE__{} = prepared) do
    case SnapshotCommit.commit(prepared.snapshot_commit) do
      {:ok, _projection} ->
        {prepared.updated_state, prepared.success_effects}

      {:error, reason} ->
        {prepared.previous_state, prepared.failure_effects.(reason)}
    end
  end
end
