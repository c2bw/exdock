defmodule Exdock.Server.NodeLifecycle.Policy do
  @moduledoc """
  Pure node lifecycle decisions.

  State transitions are supplied as data and external work is returned as a
  list of effects for the lifecycle handler to interpret.
  """

  alias Exdock.Runtime.Command
  alias Exdock.Server.NodeLifecycle.EffectPlan
  alias Exdock.Server.State
  alias Exdock.Server.State.Change.Outcome

  @type effect ::
          {:log, Logger.level(), String.t()}
          | {:state_effects, State.t(), [term()]}
          | {:pubsub, String.t(), term()}
          | {:event, term(), map()}
          | {:command, term(), term()}

  @spec connected(State.Transition.result(), String.t()) :: {State.t(), [effect()]}
  def connected(transition, node) when is_binary(node) do
    {state, transition_effects} = resolve_transition(transition)

    effects =
      EffectPlan.new(
        diagnostics: [{:log, :info, "Node [#{node}] is up"}],
        state_transition: transition_effects,
        publications: [
          {:pubsub, "nodechange", {:nodechange, :up, node}},
          {:event, :cluster, %{kind: :node_up, node: node}},
          {:event, {:node, node}, %{kind: :connected}}
        ],
        commands: [
          {:command, nil, Command.Cluster.refresh_node(node, :hidden)}
        ]
      )
      |> EffectPlan.effects()

    {state, effects}
  end

  @spec disconnected({State.t(), [term()]}, String.t()) :: {State.t(), [effect()]}
  def disconnected({%State{} = state, state_effects}, node)
      when is_list(state_effects) and is_binary(node) do
    effects =
      EffectPlan.new(
        diagnostics: [{:log, :info, "Node [#{node}] is down"}],
        state_transition: [{:state_effects, state, state_effects}],
        publications: [
          {:pubsub, "nodechange", {:nodechange, :down, node}},
          {:event, :cluster, %{kind: :node_down, node: node}},
          {:event, {:node, node}, %{kind: :disconnected}}
        ]
      )
      |> EffectPlan.effects()

    {state, effects}
  end

  defp resolve_transition(%Outcome{state: %State{} = state, effects: state_effects})
       when is_list(state_effects),
       do: {state, [{:state_effects, state, state_effects}]}

  defp resolve_transition({:error, reason, %State{} = state}),
    do: {state, [{:log, :error, "Unable to hydrate node: #{inspect(reason)}"}]}
end
