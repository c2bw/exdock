defmodule Exdock.Database.NodeNameTest do
  use ExUnit.Case, async: true

  alias Exdock.Database.NodeName

  test "dumps validated runtime node strings" do
    assert NodeName.dump("node_a") == "node_a"
  end

  test "keeps validated node ids as stored strings" do
    assert NodeName.stored!("node_a") == "node_a"
  end

  test "loads database names as runtime strings" do
    assert NodeName.load("node_a") == "node_a"
  end

  test "keeps struct node fields in stored format" do
    assert NodeName.to_stored_format(%{node: "node_a"}) == %{node: "node_a"}
  end

  test "keeps stored node fields as runtime strings" do
    assert NodeName.from_stored_format(%{node: "node_a"}) == %{node: "node_a"}
  end

  test "builds canonical database query fragments from node strings" do
    assert NodeName.query("node_a") == [node: "node_a"]
  end

  test "rejects malformed DB node values that do not match connection validation rules" do
    assert_raise ArgumentError, fn -> NodeName.load("") end
    assert_raise ArgumentError, fn -> NodeName.load("has spaces") end
    assert_raise ArgumentError, fn -> NodeName.load("local") end
    assert_raise ArgumentError, fn -> NodeName.stored!("has spaces") end
  end

  test "rejects non-binary values at the DB boundary" do
    assert_raise ArgumentError, fn -> NodeName.load(123) end
    assert_raise ArgumentError, fn -> NodeName.load(%{}) end
  end
end
