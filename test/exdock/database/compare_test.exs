defmodule Exdock.Database.CompareTest do
  use ExUnit.Case, async: true

  alias Ecto.Schema.Metadata
  alias Exdock.Database.Nodes
  alias Exdock.Database.Compare

  test "compares maps with nested values regardless of key and list order" do
    left = %{
      name: "app",
      metrics: [1, 2, %{kind: "cache", labels: [3, 1]}],
      active: true
    }

    right = %{active: true, name: "app", metrics: [%{labels: [1, 3], kind: "cache"}, 2, 1]}

    assert Compare.compare(left, right)
  end

  test "returns false when comparable values differ" do
    assert Compare.compare([1, 2, 3], [1, 2, 4]) == false
  end

  test "compares structs by normalized values and ignores metadata differences" do
    fetched_at = ~U[2026-01-01 12:00:00Z]

    from_db = %Nodes{node: "node", fetched_at: fetched_at}

    from_cache =
      from_db
      |> Map.put(:__meta__, %Metadata{
        state: :loaded,
        source: "nodes",
        context: nil,
        schema: Nodes,
        prefix: nil
      })

    assert Compare.compare(from_db, from_cache)
  end
end
