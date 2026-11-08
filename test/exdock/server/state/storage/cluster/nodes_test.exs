defmodule Exdock.Server.State.Storage.NodesTest do
  use Exdock.DataCase, async: false

  alias Exdock.Server.State
  alias Exdock.Server.State.Domains.Nodes, as: NodesDomain
  alias Exdock.Runtime.Mutation
  alias Exdock.Server.State.Storage.Cluster
  alias Exdock.Server.State.Storage.Nodes
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Server.State.Change.{Outcome, Plan}
  alias Exdock.Domain.Node

  test "setting change updates an existing node and requests an immediate broadcast" do
    state = state_with_node("node", "https://old.example")
    assert {:ok, payload} = Mutation.node_setting("node", :web_ui, "new.example")

    assert %Outcome{
             state: %State{cluster: %Cluster{storage: storage}},
             broadcast_opts: [delayed: false, force: true],
             effects: []
           } =
             NodesDomain.plan(state, payload) |> Plan.execute()

    assert %Node{settings: %Node.Settings{web_ui: "https://new.example"}} = Nodes.get(storage, "node")
    assert %Node.Settings{web_ui: "https://new.example"} = NodePersistence.load_settings("node")
  end

  test "setting change for a missing node is rejected" do
    state = state_with_node("node", "https://old.example")
    assert {:ok, payload} = Mutation.node_setting("missing", :web_ui, "https://new.example")

    assert {:error, {:node_setting_persistence, :node_not_found}} =
             NodesDomain.plan(state, payload) |> Plan.execute()
  end

  test "reload refreshes imported node settings without replacing live node data" do
    state = state_with_node("node", "https://old.example")

    assert {:ok, _settings} =
             Node.Settings.default()
             |> Node.Settings.set(:web_ui, "https://imported.example")
             |> NodePersistence.insert_settings("node")

    assert %State{cluster: %Cluster{storage: storage}} = NodesDomain.reload(state)

    assert %Node{fetched_at: nil, settings: %Node.Settings{web_ui: "https://imported.example"}} =
             Nodes.get(storage, "node")
  end

  test "retrieve exposes the durable string-keyed node map" do
    state = state_with_node("node", "https://old.example")

    assert %{"node" => %Node{}} = Nodes.full_string_map(state)
  end

  test "cluster data accepts string node names at the API boundary" do
    state = state_with_node("node", "https://old.example")

    assert %Cluster.NodeData{node: "node"} = Cluster.data(state, "node")
  end

  test "cluster info exposes durable string-keyed node summaries" do
    state = state_with_node("node", "https://old.example")

    assert %{"node" => %Cluster.Info.InfoData{}} = Cluster.info(state).by_node_string
  end

  test "broadcast exposes the durable string-keyed node map" do
    state = state_with_node("node", "https://old.example")

    assert {%{"node" => %Node{}}, []} = NodesDomain.broadcast(state)
  end

  test "live metadata survives refresh timestamps, is removed on disconnect, and is replaced on reconnect" do
    first_metadata = %{"platform" => "linux/amd64"}
    second_metadata = %{"platform" => "linux/arm64"}

    assert {:ok, cluster} = Cluster.load(Cluster.new(), "node", first_metadata)
    state = %State{cluster: cluster}

    assert %Node{metadata: ^first_metadata} = Nodes.get(cluster.storage, "node")

    refreshed_storage = Nodes.update_fetch_time(cluster.storage, "node", ~U[2026-07-31 10:00:00Z])
    assert %Node{metadata: ^first_metadata} = Nodes.get(refreshed_storage, "node")

    disconnected_cluster = Cluster.remove(%Cluster{cluster | storage: refreshed_storage}, "node")
    assert Nodes.get(disconnected_cluster.storage, "node") == nil

    assert {:ok, reconnected_cluster} = Cluster.load(disconnected_cluster, "node", second_metadata)
    assert %Node{metadata: ^second_metadata} = Nodes.get(reconnected_cluster.storage, "node")

    assert %{"node" => %Node{metadata: ^second_metadata}} =
             Nodes.full_string_map(%State{state | cluster: reconnected_cluster})
  end

  defp state_with_node(node, web_ui) do
    node_data =
      node
      |> Node.default()
      |> Map.update!(:settings, &Node.Settings.set(&1, :web_ui, web_ui))

    storage =
      Cluster.new().storage
      |> Nodes.set(node, node_data)

    %State{cluster: %Cluster{storage: storage}}
  end
end
