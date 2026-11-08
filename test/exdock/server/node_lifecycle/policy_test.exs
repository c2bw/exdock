defmodule Exdock.Server.NodeLifecycle.PolicyTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.NodeLifecycle.Policy
  alias Exdock.Server.State
  alias Exdock.Server.State.Change.Outcome

  test "connected retains a hydrated state and describes all external effects" do
    state = %State{revision: 2}
    state_effects = [{:broadcast, :nodes, nil}]

    assert {^state, effects} = Policy.connected(Outcome.new(state, state_effects), "node-a")
    assert {:state_effects, state, state_effects} in effects
    assert {:pubsub, "nodechange", {:nodechange, :up, "node-a"}} in effects
    assert {:event, :cluster, %{kind: :node_up, node: "node-a"}} in effects
    assert {:event, {:node, "node-a"}, %{kind: :connected}} in effects
    assert {:command, nil, _refresh_command} = List.last(effects)
  end

  test "connected retains the prior state and reports hydration failures as effects" do
    state = %State{revision: 1}

    assert {^state, effects} =
             Policy.connected({:error, :invalid_snapshot, state}, "node-a")

    assert {:log, :error, "Unable to hydrate node: :invalid_snapshot"} in effects
    refute Enum.any?(effects, &match?({:state_effects, _, _}, &1))
    assert {:command, nil, _refresh_command} = List.last(effects)
  end

  test "disconnected returns the new state with its effects" do
    state = %State{revision: 3}
    state_effects = [{:broadcast, :nodes, nil}]

    assert {^state, effects} = Policy.disconnected({state, state_effects}, "node-a")
    assert {:state_effects, state, state_effects} in effects
    assert {:pubsub, "nodechange", {:nodechange, :down, "node-a"}} in effects
    assert {:event, {:node, "node-a"}, %{kind: :disconnected}} in effects
  end
end
