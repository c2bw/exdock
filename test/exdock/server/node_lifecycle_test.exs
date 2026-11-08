defmodule Exdock.Server.NodeLifecycleTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.NodeLifecycle
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage

  test "reset disconnects every online node through the normal lifecycle" do
    storage =
      Enum.reduce(["node-a", "node-b"], Storage.Cluster.new().storage, fn node, storage ->
        Storage.Nodes.set(storage, node, Exdock.Domain.Node.default(node))
      end)

    state = %State{revision: 0, cluster: %Storage.Cluster{storage: storage}}
    updated = NodeLifecycle.reset(state, __MODULE__)
    assert Storage.Nodes.list(updated.cluster.storage) == []
    assert updated.revision == 2

    for node <- ["node-a", "node-b"] do
      assert_receive {:lifecycle_effects, effects}
      assert Enum.any?(effects, &match?({:pubsub, "nodechange", {:nodechange, :down, ^node}}, &1))
    end

    assert NodeLifecycle.reset(updated, __MODULE__) == updated
    refute_received {:lifecycle_effects, _}
  end

  test "uses the injected lifecycle effect handler" do
    state = %State{revision: 0, cluster: Storage.Cluster.new()}

    assert %State{revision: 1} = NodeLifecycle.disconnected(state, "node-a", __MODULE__)
    assert_received {:lifecycle_effects, effects}
    assert {:pubsub, "nodechange", {:nodechange, :down, "node-a"}} in effects
  end

  def run(effects) do
    send(self(), {:lifecycle_effects, effects})
    :ok
  end
end
