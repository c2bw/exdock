defmodule Exdock.Server.NodeHydrationRecoveryTest do
  use Exdock.Server.State.ClientMessagesCase, async: false

  alias Exdock.Database
  alias Exdock.Server.{Jobs, NodeLifecycle}
  alias Exdock.Server.State.Storage

  test "a failed saved snapshot can recover through the connected node's live refresh" do
    populated = commit_client_message(base_state(), node_refresh_message(container_result()))
    saved_node = Storage.Nodes.get(populated.cluster.storage, "node")
    saved_node = %{saved_node | settings: %{saved_node.settings | web_ui: "https://node.example"}}
    :ok = Storage.Persistence.Node.insert(saved_node)
    # A missing tag reference makes saved container hydration return a LoadReport.
    Exdock.Repo.delete_all(Database.ImageTagInfo)
    metadata = %{"platform" => "linux/amd64"}
    assert {:error, %Storage.Persistence.LoadReport{}} = Storage.Cluster.load(Storage.Cluster.new(), "node", metadata)

    user = Exdock.Domain.UserSettings.default()
    empty = %{base_state() | cluster: Storage.Cluster.new(), settings: %Storage.Settings{user: %{user.user => user}}}
    connected = NodeLifecycle.connected(empty, "node", metadata, __MODULE__)
    assert %Exdock.Domain.Node{metadata: ^metadata} = Storage.Nodes.get(connected.cluster.storage, "node")
    assert_receive {:lifecycle_effects, effects}
    assert {:command, nil, _refresh_command} = List.last(effects)
    assert %Jobs.Detail{} = Jobs.Client.Node.refresh_node(connected, "node")

    recovered = commit_client_message(connected, node_refresh_message(container_result()))
    assert [%{id: "container-id"}] = Storage.Containers.list_node(recovered.cluster.storage, "node")
    assert {:ok, reloaded} = Storage.Cluster.load(Storage.Cluster.new(), "node", metadata)
    assert [%{id: "container-id"}] = Storage.Containers.list_node(reloaded.storage, "node")

    assert Storage.Nodes.get(recovered.cluster.storage, "node").settings.web_ui == "https://node.example"
  end

  def run(effects) do
    send(self(), {:lifecycle_effects, effects})
    :ok
  end
end
