defmodule Exdock.EventsTest do
  use ExUnit.Case, async: true

  alias Exdock.Events

  test "publishes operation acceptance with a revisioned envelope" do
    assert :ok = Events.subscribe(:operations)
    assert :ok = Events.operation_accepted("operation-id", :refresh_node)

    assert_receive {:exdock_event, :operations, revision, %{id: "operation-id", kind: :refresh_node, state: :accepted}}

    assert is_integer(revision) and revision > 0
  end

  test "assigns monotonically increasing revisions" do
    assert :ok = Events.subscribe(:activity)
    assert :ok = Events.publish(:activity, :first)
    assert :ok = Events.publish(:activity, :second)

    assert_receive {:exdock_event, :activity, first_revision, :first}
    assert_receive {:exdock_event, :activity, second_revision, :second}
    assert second_revision > first_revision
  end

  test "keeps node-specific topics isolated" do
    assert :ok = Events.subscribe({:node, "node-a"})
    assert :ok = Events.publish({:node, "node-b"}, :other)
    refute_receive {:exdock_event, {:node, "node-b"}, _revision, :other}

    assert :ok = Events.publish({:node, "node-a"}, :updated)
    assert_receive {:exdock_event, {:node, "node-a"}, revision, :updated}
    assert is_integer(revision)
  end

  test "page subscriptions exclude optional projection topics that were not requested" do
    assert :ok = Events.subscribe_page([:nodes, :containers])

    assert :ok = Events.publish(:repositories, :repository_update)
    refute_receive {:exdock_event, :repositories, _revision, :repository_update}

    assert :ok = Events.publish(:cluster, :cluster_update)
    assert_receive {:exdock_event, :cluster, _revision, :cluster_update}
  end

  test "page subscriptions include repositories when requested" do
    assert :ok = Events.subscribe_page([:repositories])
    assert :ok = Events.publish(:repositories, :repository_update)
    assert_receive {:exdock_event, :repositories, _revision, :repository_update}
  end
end
