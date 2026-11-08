defmodule Exdock.Domain.NodeTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Domain.Node

  test "insert/1 stores settings even before node data has been fetched" do
    node = Node.default("node")
    node = %{node | settings: Node.Settings.set(node.settings, :web_ui, "http://node.local")}

    assert :ok = NodePersistence.insert(node)
    assert Database.Nodes.load("node") == nil
    assert %Database.NodeSettings{node: "node", web_ui: "http://node.local"} = Database.NodeSettings.load("node")
    assert %Node.Settings{web_ui: "http://node.local"} = NodePersistence.load_settings("node")
  end

  test "insert/1 stores fetched node data and settings together" do
    node =
      "node"
      |> Node.default()
      |> Node.put_metadata(%{"platform" => "linux/amd64"})
      |> Node.set_fetched_at(DateTime.utc_now())

    assert :ok = NodePersistence.insert(node)
    assert %Database.Nodes{node: "node", fetched_at: fetched_at} = Database.Nodes.load("node")
    assert %Database.NodeSettings{node: "node", web_ui: ""} = Database.NodeSettings.load("node")
    assert fetched_at == node.fetched_at

    assert %Node{metadata: %{}} = NodePersistence.load("node")
  end

  test "load/1 uses default settings when only fetched node data exists" do
    node =
      "node"
      |> Node.default()
      |> Node.set_fetched_at(DateTime.utc_now())

    assert {:ok, %Database.Nodes{}} =
             %{node: node.node, fetched_at: node.fetched_at}
             |> Database.Nodes.new()
             |> Database.Nodes.insert()

    assert %Node{node: "node", fetched_at: fetched_at, settings: %Node.Settings{web_ui: ""}} =
             NodePersistence.load("node")

    assert fetched_at == node.fetched_at
  end

  test "node setting validation canonicalizes URLs and rejects unsupported inputs" do
    assert {:ok, {:web_ui, "https://node.example"}} =
             Node.Settings.validate_setting("web_ui", "node.example")

    assert {:error, {:unknown_node_setting, :unknown}} =
             Node.Settings.validate_setting(:unknown, "value")

    assert {:error, {:invalid_node_setting_value, :web_ui}} =
             Node.Settings.validate_setting(:web_ui, 123)
  end
end
