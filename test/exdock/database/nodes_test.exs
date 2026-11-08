defmodule Exdock.Database.NodesTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database.Nodes

  test "round-trips string node names" do
    fetched_at = ~U[2026-06-30 15:43:22.123456Z]

    assert {:ok, %Nodes{node: "node", fetched_at: ~U[2026-06-30 15:43:22Z]}} =
             %Nodes{node: "node", fetched_at: fetched_at}
             |> Nodes.insert()

    assert %Nodes{node: "node", fetched_at: ~U[2026-06-30 15:43:22Z]} = Nodes.load("node")
  end

  test "load/1 accepts validated string node keys" do
    assert {:ok, %Nodes{node: "node", fetched_at: ~U[2026-06-30 15:43:22Z]}} =
             Nodes.insert(%Nodes{node: "node", fetched_at: ~U[2026-06-30 15:43:22Z]})

    assert %Nodes{node: "node", fetched_at: ~U[2026-06-30 15:43:22Z]} = Nodes.load("node")
  end

  test "insert/1 upserts fetched_at for an existing node" do
    assert {:ok, %Nodes{node: "node"}} = Nodes.insert(%Nodes{node: "node", fetched_at: ~U[2026-06-30 15:43:22Z]})
    assert {:ok, %Nodes{node: "node"}} = Nodes.insert(%Nodes{node: "node", fetched_at: ~U[2026-07-01 10:00:00Z]})

    assert [%Nodes{node: "node", fetched_at: ~U[2026-07-01 10:00:00Z]}] = Nodes.load_all()
  end
end
