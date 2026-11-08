defmodule Exdock.Server.State.Storage.Cluster.Utils.NodeStorageTest do
  use ExUnit.Case, async: true

  alias Exdock.Domain
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage

  test "stores typed node, image, and container collections independently" do
    node = Domain.Node.default("node_a")
    image = %Domain.Image{id: "image-a"}
    container = %Domain.Container{id: "container-a"}

    storage =
      NodeStorage.new()
      |> NodeStorage.put_node("node_a", node)
      |> NodeStorage.put_images("node_a", [image])
      |> NodeStorage.put_containers("node_a", [container])

    assert NodeStorage.get_node(storage, "node_a") == node
    assert NodeStorage.get_images(storage, "node_a") == [image]
    assert NodeStorage.get_containers(storage, "node_a") == [container]
    assert NodeStorage.get_node(storage, "missing") == nil
    assert NodeStorage.get_images(storage, "missing") == []
    assert NodeStorage.get_containers(storage, "missing") == []
  end

  test "update_node uses a typed default for missing values" do
    increment = fn node ->
      count = Map.get(node.metadata, :updates, 0)
      Domain.Node.put_metadata(node, %{updates: count + 1})
    end

    storage =
      NodeStorage.new()
      |> NodeStorage.update_node("node_a", Domain.Node.default("node_a"), increment)
      |> NodeStorage.update_node("node_a", Domain.Node.default("node_a"), increment)

    assert %Domain.Node{metadata: %{updates: 2}} = NodeStorage.get_node(storage, "node_a")
  end

  test "remove deletes a node from every typed collection" do
    storage =
      NodeStorage.new()
      |> NodeStorage.put_node("node_a", Domain.Node.default("node_a"))
      |> NodeStorage.put_images("node_a", [%Domain.Image{id: "image-a"}])
      |> NodeStorage.put_containers("node_a", [%Domain.Container{id: "container-a"}])
      |> NodeStorage.remove("node_a")

    assert NodeStorage.get_node(storage, "node_a") == nil
    assert NodeStorage.get_images(storage, "node_a") == []
    assert NodeStorage.get_containers(storage, "node_a") == []
  end

  test "map and aggregate helpers preserve durable node keys" do
    node_a = Domain.Node.default("node.a")
    node_b = Domain.Node.default("node_b")
    image = %Domain.Image{id: "image-a"}

    storage =
      NodeStorage.new()
      |> NodeStorage.put_node("node.a", node_a)
      |> NodeStorage.put_node("node_b", node_b)
      |> NodeStorage.put_images("node.a", [image])

    assert NodeStorage.nodes_map(storage) == %{"node.a" => node_a, "node_b" => node_b}
    assert Enum.sort(NodeStorage.node_keys(storage)) == ["node.a", "node_b"]
    assert NodeStorage.images_map(storage) == %{"node.a" => [image]}
    assert NodeStorage.all_images(storage) == [image]
    assert NodeStorage.all_containers(storage) == []
  end
end
