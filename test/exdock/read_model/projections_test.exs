defmodule Exdock.ReadModel.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Exdock.ReadModel.{ClusterNode, Page, Projections}
  alias Exdock.Runtime.EventCatalog

  test "exposes projection assigns from one registry" do
    assert Projections.valid_keys?([:nodes, :containers, :repositories])
    refute Projections.valid_keys?([:nodes, :unknown])
    assert Projections.unknown_keys([:nodes, :unknown]) == [:unknown]

    assert Projections.assigns([:containers, :repositories]) ==
             [:containers, :containers_extended, :repositories]

    assert Projections.topics([:nodes, :containers, :repositories]) ==
             [:cluster, :repositories]
  end

  test "owns source topic routing for queries and broadcasts" do
    assert Projections.sources() == EventCatalog.sources()
    assert Projections.topic_for_source(:containers) == {:ok, :cluster}
    assert Projections.topic_for_source(:server_configuration) == {:ok, :cluster}
    assert Projections.topic_for_source(:tags) == {:ok, :repositories}
    assert Projections.topic_for_source(:status) == {:ok, :activity}
    assert Projections.topic_for_source(:unknown) == :error

    refute Projections.known_source?(:containers_extended)
    refute Projections.known_source?(:nodes_list)
  end

  test "every event source declares and satisfies its consumer policy" do
    handled_sources = MapSet.new(Projections.handled_sources())

    for source <- EventCatalog.sources() do
      case EventCatalog.consumer_policy_for(source) do
        {:ok, :assigns} -> assert MapSet.member?(handled_sources, source)
        {:ok, :routing_only} -> refute MapSet.member?(handled_sources, source)
      end
    end

    assert EventCatalog.consumer_policy_for(:unknown) == :error
  end

  test "every event source declares revision and base subscription policy" do
    runtime_sources = MapSet.new(EventCatalog.sources_for_revision(:runtime))
    activity_sources = MapSet.new(EventCatalog.sources_for_revision(:activity))

    assert MapSet.disjoint?(runtime_sources, activity_sources)
    assert MapSet.union(runtime_sources, activity_sources) == MapSet.new(EventCatalog.sources())
    assert EventCatalog.base_page_topics() == [:activity, :cluster, :settings]
  end

  test "registered projection assigns are fields on the page read model" do
    page_fields = %Page{} |> Map.from_struct() |> Map.keys() |> MapSet.new()
    projection_fields = Projections.keys() |> Projections.assigns() |> MapSet.new()

    assert MapSet.subset?(projection_fields, page_fields)
  end

  test "registered modules own query and broadcast projection" do
    Enum.each(Projections.keys(), fn key ->
      module = Projections.module_for(key)

      assert Code.ensure_loaded?(module)
      assert function_exported?(module, :from_query, 1)
      assert function_exported?(module, :from_broadcast, 1)
    end)
  end

  test "builds runtime and activity revision watermarks" do
    revisions = Projections.initial_revisions(12, 7)

    assert revisions.nodes == 12
    assert revisions.containers == 12
    assert revisions.repositories == 12
    assert revisions.tags == 12
    assert revisions.server_configuration == 12
    assert revisions.status == 7
    assert revisions.log == 7
  end

  test "normalizes broadcast payloads into replacement assigns" do
    assert {:ok, %{repositories: [:repository]}} =
             Projections.broadcast_assigns(:repositories, [:repository])

    node = %ClusterNode{node: "node"}

    assert {:ok, %{nodes: %{"node" => ^node}, nodes_list: ["node"]}} =
             Projections.broadcast_assigns(:nodes, %{"node" => node})

    assert Projections.broadcast_assigns(:tags, :payload) == :ignored
    assert Projections.broadcast_assigns(:unknown, :payload) == :unknown
  end
end
