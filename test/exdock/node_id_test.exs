defmodule Exdock.NodeIdTest do
  use ExUnit.Case, async: true

  alias Exdock.NodeId

  test "normalizes valid node identifiers without allocating atoms" do
    identifier = "node-01.eu_west"

    assert NodeId.normalize(identifier) == {:ok, identifier}
    assert NodeId.validate(identifier) == :ok
    assert NodeId.valid?(identifier)
  end

  test "rejects atoms and malformed external identifiers" do
    assert NodeId.normalize(:node) == {:error, :invalid_type}
    assert NodeId.validate(:node) == {:error, :invalid_format}
    assert NodeId.normalize("has spaces") == {:error, :invalid_format}
    refute NodeId.valid?("local")
  end

  test "normalize!/1 returns valid strings and raises for invalid input" do
    assert NodeId.normalize!("known-node") == "known-node"
    assert_raise ArgumentError, fn -> NodeId.normalize!("has spaces") end
    assert_raise ArgumentError, fn -> apply(NodeId, :normalize!, [%{}]) end
  end
end
