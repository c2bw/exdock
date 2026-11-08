defmodule Exdock.Server.State.Storage.Persistence.TransactionTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.Transaction

  test "commits a successful stateful reduction" do
    assert {:ok, 6} =
             Transaction.run(fn ->
               Transaction.reduce([1, 2, 3], 0, fn value, total -> {:ok, total + value} end)
             end)
  end

  test "rolls back earlier writes when a later step fails" do
    assert {:error, :stop} =
             Transaction.run(fn ->
               node = Database.Nodes.new(%{node: "node-a", fetched_at: ~U[2026-07-31 12:00:00Z]})
               assert {:ok, _node} = Database.Nodes.insert(node)
               {:error, :stop}
             end)

    assert Database.Nodes.load("node-a") == nil
  end
end
