defmodule Exdock.Server.Jobs.State.LinkedTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.State.Linked

  test "groups duplicate ids by the running id that owns the work" do
    linked =
      Linked.new()
      |> Linked.add("duplicate-a", "running")
      |> Linked.add("duplicate-b", "running")
      |> Linked.add("other-duplicate", "other-running")

    assert Linked.get_linked(linked, "running") |> Enum.sort() == ["duplicate-a", "duplicate-b"]
    assert Linked.get_linked(linked, "other-running") == ["other-duplicate"]
    assert Linked.get_linked(linked, "missing") == []
  end

  test "ignores jobs that were not linked to an existing running job" do
    linked = Linked.add(Linked.new(), "duplicate", nil)

    assert linked == Linked.new()
  end

  test "removes all duplicate links for a completed running id" do
    linked =
      Linked.new()
      |> Linked.add("duplicate-a", "running")
      |> Linked.add("duplicate-b", "running")
      |> Linked.add("other-duplicate", "other-running")
      |> Linked.remove_link("running")

    assert Linked.get_linked(linked, "running") == []
    assert Linked.get_linked(linked, "other-running") == ["other-duplicate"]
  end
end
