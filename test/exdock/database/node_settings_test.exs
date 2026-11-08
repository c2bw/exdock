defmodule Exdock.Database.NodeSettingsTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database.NodeSettings

  test "round-trips string node names" do
    assert {:ok, %NodeSettings{node: "node", web_ui: "http://node.local"}} =
             %NodeSettings{node: "node", web_ui: "http://node.local"}
             |> NodeSettings.insert()

    assert %NodeSettings{node: "node", web_ui: "http://node.local"} = NodeSettings.load("node")
  end

  test "load/1 accepts validated string node keys" do
    assert {:ok, %NodeSettings{node: "node", web_ui: "http://node.local"}} =
             %NodeSettings{node: "node", web_ui: "http://node.local"}
             |> NodeSettings.insert()

    assert %NodeSettings{node: "node", web_ui: "http://node.local"} = NodeSettings.load("node")
  end

  test "insert/1 keeps blank web_ui as the default value" do
    assert {:ok, %NodeSettings{node: "node", web_ui: ""}} =
             %NodeSettings{node: "node", web_ui: ""}
             |> NodeSettings.insert()

    assert %NodeSettings{node: "node", web_ui: ""} = NodeSettings.load("node")
  end

  test "insert/1 upserts settings for an existing node" do
    assert {:ok, %NodeSettings{}} = NodeSettings.insert(%NodeSettings{node: "node", web_ui: ""})

    assert {:ok, %NodeSettings{}} =
             NodeSettings.insert(%NodeSettings{node: "node", web_ui: "http://node.local"})

    assert [%NodeSettings{node: "node", web_ui: "http://node.local"}] = NodeSettings.load_all()
  end
end
