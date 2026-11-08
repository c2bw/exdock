defmodule Exdock.Server.Jobs.Client.NodeTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Client.Node, as: NodeJobs
  alias Exdock.Server.Jobs.Payload.NodeRefresh
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage
  alias Exdock.Domain

  test "returns no cluster refresh work when there are no nodes" do
    assert NodeJobs.refresh_cluster(state_with_cluster(Storage.Cluster.new())) == nil
  end

  test "builds a cluster refresh detail with initial container state" do
    detail =
      cluster_with_nodes(["node_a", "node_b"])
      |> state_with_cluster()
      |> put_containers("node_a", [
        container("app", running?: true),
        container("worker", running?: false)
      ])
      |> NodeJobs.refresh_cluster()

    assert %Jobs.Detail{name: :node_refresh, spec_list: [{%Jobs.Spec{} = spec, _id}]} = detail
    assert %Jobs.Spec.Remote{nodes: nodes} = spec.location
    assert Enum.sort(nodes) == ["node_a", "node_b"]
    assert spec.parameters == [%{"retrieve_resources" => false}]

    assert spec.data ==
             NodeRefresh.new(
               %{
                 "node_a" => [{"app", {:before, true}}, {"worker", {:before, false}}],
                 "node_b" => []
               },
               %{nodes: ["node_a", "node_b"], containers: %{}},
               hidden: false
             )
  end

  test "builds a single-node refresh and can hide refresh logging" do
    detail =
      cluster_with_nodes(["node_a", "node_b"])
      |> state_with_cluster()
      |> put_containers("node_b", [container("db", running?: true)])
      |> NodeJobs.refresh_node("node_b", :hidden)

    assert %Jobs.Detail{name: :node_refresh, spec_list: [{%Jobs.Spec{} = spec, _id}]} = detail
    assert %Jobs.Spec.Remote{nodes: ["node_b"]} = spec.location

    assert spec.data ==
             NodeRefresh.new(
               %{"node_b" => [{"db", {:before, true}}]},
               %{nodes: ["node_b"], containers: %{}},
               hidden: true
             )
  end

  test "returns no node refresh work when the node is missing" do
    assert NodeJobs.refresh_node(state_with_cluster(cluster_with_nodes(["node"])), "missing") == nil
  end

  defp state_with_cluster(%Storage.Cluster{} = cluster) do
    default_user = Domain.UserSettings.default_user()

    %State{
      cluster: cluster,
      settings: %Storage.Settings{user: %{default_user => Domain.UserSettings.default()}}
    }
  end

  defp cluster_with_nodes(nodes) do
    storage =
      Enum.reduce(nodes, Storage.Cluster.new().storage, fn node, storage ->
        Storage.Nodes.set(storage, node, Domain.Node.default(node))
      end)

    %Storage.Cluster{storage: storage}
  end

  defp put_containers(%State{cluster: %Storage.Cluster{storage: storage} = cluster} = state, node, containers) do
    storage = Storage.Containers.set_node(storage, node, containers)
    %{state | cluster: %{cluster | storage: storage}}
  end

  defp container(name, opts) do
    %Domain.Container{
      node: "node",
      name: name,
      core: %Domain.Container.Core{is_running: Keyword.fetch!(opts, :running?)}
    }
  end
end
