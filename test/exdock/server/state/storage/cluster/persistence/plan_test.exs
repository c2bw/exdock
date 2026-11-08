defmodule Exdock.Server.State.Storage.Cluster.Persistence.PlanTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster
  alias Exdock.Server.State.Storage.Cluster.Persistence.Plan
  alias Exdock.Domain
  alias Exdock.Domain.{Container, Image, Node}
  alias Exdock.TestFixtures.DomainImage, as: ImageFixture

  test "identical durable snapshots produce an empty persistence plan" do
    image = image()
    container = container(image)
    previous = cluster([image], [container], ~U[2026-07-21 10:00:00Z])
    current = cluster([image], [container], ~U[2026-07-21 10:01:00Z])

    assert %Plan{
             node: "node",
             node_record: nil,
             image_ids: nil,
             images: [],
             container_names: nil,
             containers: []
           } = Plan.build(previous, current, "node")
  end

  test "durable record changes are separated from identity-set synchronization" do
    previous_image = image(size: 1_024)
    current_image = image(size: 2_048)
    previous_container = container(previous_image, id: "container-old")
    current_container = container(current_image, id: "container-new")
    previous = cluster([previous_image], [previous_container], ~U[2026-07-21 10:00:00Z])
    current = cluster([current_image], [current_container], ~U[2026-07-21 10:01:00Z])

    assert %Plan{
             node_record: %Node{fetched_at: ~U[2026-07-21 10:01:00Z]},
             image_ids: nil,
             images: [^current_image],
             container_names: nil,
             containers: [^current_container]
           } = Plan.build(previous, current, "node")
  end

  test "removed records request set synchronization without queuing inserts" do
    previous_image = image()
    previous_container = container(previous_image)
    previous = cluster([previous_image], [previous_container], ~U[2026-07-21 10:00:00Z])
    current = cluster([], [], ~U[2026-07-21 10:01:00Z])

    assert %Plan{
             node_record: %Node{},
             image_ids: [],
             images: [],
             container_names: [],
             containers: []
           } = Plan.build(previous, current, "node")
  end

  defp cluster(images, containers, fetched_at) do
    storage =
      Cluster.new().storage
      |> Storage.Nodes.set("node", %{Node.default("node") | fetched_at: fetched_at})
      |> Storage.Images.set_node("node", images)
      |> Storage.Containers.set_node("node", containers)

    %Cluster{storage: storage}
  end

  defp image(opts \\ []) do
    ImageFixture.build(
      Keyword.merge(
        [
          id: "sha256:image",
          name: "example/app",
          tags: ["example/app:latest"],
          metadata: Image.Metadata.default("example/app"),
          registry_url: "example/app",
          in_use: true,
          settings: Image.Settings.default()
        ],
        opts
      )
    )
  end

  defp container(%Image{} = image, opts \\ []) do
    %Container{
      node: "node",
      name: "app",
      id: Keyword.get(opts, :id, "container-app"),
      core: %Container.Core{
        is_deleted: false,
        is_running: true,
        stack_name: "app",
        configuration: %Container.Configuration{},
        state: %Container.Core.State{restarting: false},
        image_data: %Container.Core.ImageData{
          status: :updated,
          tag_info: %Domain.TagInfo{tag: "example/app:latest"},
          image: image
        },
        settings: Container.Settings.default()
      }
    }
  end
end
