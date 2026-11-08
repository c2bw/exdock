defmodule Exdock.Server.State.Storage.ImagesTest do
  use Exdock.DataCase, async: false

  alias Exdock.Server.State.Storage.Images
  alias Exdock.Server.State.Storage.Persistence.ImageMetadata
  alias Exdock.Server.State.Storage.Persistence.ImageSettings
  alias Exdock.Runtime.Mutation
  alias Exdock.Server.State.Storage.Cluster
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Protocol.Snapshot.Image, as: ClientImage
  alias Exdock.Domain.Image
  alias Exdock.Server.State
  alias Exdock.Server.State.Domains.Images, as: ImagesDomain
  alias Exdock.Server.State.Change.{Outcome, Plan}
  alias Exdock.Server.Logging.AppendEntry
  alias Exdock.TestFixtures.DomainImage, as: ImageFixture

  test "list flattens per-node image buckets and repository urls stay unique" do
    app = image(repository_url: "https://github.com/example/app")
    db = image(repository_url: "https://github.com/example/db")
    app_copy = image(repository_url: "https://github.com/example/app")

    storage =
      NodeStorage.new()
      |> NodeStorage.put_images("node_a", [app, db])
      |> NodeStorage.put_images("node_b", [app_copy])

    assert Images.list(storage) == [app, db, app_copy]
    assert Images.repositories_urls(storage) == ["https://github.com/example/app", "https://github.com/example/db"]
  end

  test "image info groups locked, unused, and in-use images" do
    info =
      [
        image(size: 100, shared_size: 10, in_use: true, locked: false),
        image(size: 200, shared_size: 20, in_use: false, locked: false),
        image(size: 300, shared_size: 30, in_use: false, locked: true)
      ]
      |> Images.Info.new()

    assert info.combined.images_count == 3
    assert info.combined.total_bytesize == 600
    assert info.combined.shared_bytesize == 60
    assert info.combined.counters.status.in_use == %{count: 1, percentage: 33.4}
    assert info.combined.counters.status.unused == %{count: 1, percentage: 33.4}
    assert info.combined.counters.status.locked == %{count: 1, percentage: 33.4}

    assert info.unused.images_count == 1
    assert info.unused.counters.status.unused == %{count: 1, percentage: 100.0}

    assert info.in_use.images_count == 1
    assert info.in_use.counters.status.in_use == %{count: 1, percentage: 100.0}
  end

  test "image info returns zeroed counters for empty image lists" do
    info = Images.Info.new([])

    assert info.combined.images_count == 0
    assert info.combined.total_bytesize == 0
    assert info.combined.shared_bytesize == 0
    assert info.combined.counters.status.locked == %{count: 0, percentage: 0}
    assert info.unused.images_count == 0
    assert info.in_use.images_count == 0
  end

  test "maps expose durable string-keyed image data" do
    app = image(repository_url: "https://github.com/example/app")

    storage =
      NodeStorage.new()
      |> NodeStorage.put_images("node_a", [app])

    state = %State{cluster: %Cluster{storage: storage}}

    assert %{"node_a" => [^app]} = Images.full_string_map(state)
    assert %{"node_a" => [^app]} = Images.full_string_map(state)
  end

  test "broadcast exposes the durable string-keyed image map" do
    app = image(repository_url: "https://github.com/example/app")

    storage =
      NodeStorage.new()
      |> NodeStorage.put_images("node_a", [app])

    state = %State{cluster: %Cluster{storage: storage}}

    assert {%{"node_a" => [^app]}, []} = ImagesDomain.broadcast(state)
  end

  test "set_image updates one image without carrying persistence state" do
    current = image(id: "sha256:base", node: "node_a", size: 1024, build_date: ~U[2026-06-30 15:43:22Z])
    storage = NodeStorage.new() |> NodeStorage.put_images("node_a", [current])

    unchanged = Images.set_image(storage, "node_a", current)

    assert Images.list_node(unchanged, "node_a") == [current]

    changed = %{current | size: 2048}
    changed_storage = Images.set_image(storage, "node_a", changed)

    assert Images.list_node(changed_storage, "node_a") == [changed]
  end

  test "make/4 rebuilds image snapshots without persistence effects" do
    previous =
      image(
        id: "sha256:app",
        name: "example/app",
        size: 1024,
        repository_url: "https://old.example/app"
      )

    storage = NodeStorage.new() |> NodeStorage.put_images("node_a", [previous])

    client_image = %ClientImage{
      id: "sha256:app",
      name: "example/app",
      tags: ["example/app:latest"],
      digest: "sha256:digest",
      size: 2048,
      shared_size: 64,
      build_date: ~U[2026-06-30 15:43:22Z]
    }

    refreshed = Images.make(storage, "node_a", [client_image], ["sha256:app"])
    [snapshot] = Images.list_node(refreshed, "node_a")

    assert snapshot.size == 2048
    assert snapshot.metadata.repository_url == "https://old.example/app"
    assert snapshot.in_use == true
    assert refreshed.images.entries == %{"node_a" => [snapshot]}
    assert refreshed.nodes.entries == %{}
    assert refreshed.containers.entries == %{}
  end

  test "repository_url overrides reload image metadata from storage for every node" do
    source =
      image(
        name: "example/app",
        id: "sha256:first",
        node: "node_a",
        metadata: %Image.Metadata{repository_url: "https://old.example/app"}
      )

    mirrored =
      image(
        name: "example/app",
        id: "sha256:second",
        node: "node_b",
        metadata: %Image.Metadata{repository_url: "https://old.example/app"}
      )

    state =
      NodeStorage.new()
      |> NodeStorage.put_images("node_a", [source])
      |> NodeStorage.put_images("node_b", [mirrored])
      |> then(&%State{cluster: %Cluster{storage: &1}})

    assert {:ok, payload} =
             Mutation.image_repository_url("example/app", "https://new.example/app")

    assert %Outcome{
             state: %State{cluster: %Cluster{storage: updated}},
             broadcast_opts: [delayed: false, force: true],
             effects: [{:log_entry, %AppendEntry{message_name: :repository_overrides, message_data: {1}}}]
           } =
             ImagesDomain.plan(state, payload) |> Plan.execute()

    assert ["https://new.example/app", "https://new.example/app"] ==
             updated
             |> Images.list()
             |> Enum.map(& &1.metadata.repository_url)
             |> Enum.sort()
  end

  test "repository_url list overrides update each matching image name" do
    app = image(name: "example/app", metadata: %Image.Metadata{repository_url: "https://old.example/app"})
    db = image(name: "example/db", id: "sha256:db", metadata: %Image.Metadata{repository_url: "https://old.example/db"})

    state =
      NodeStorage.new()
      |> NodeStorage.put_images("node_a", [app, db])
      |> then(&%State{cluster: %Cluster{storage: &1}})

    assert {:ok, payload} =
             Mutation.image_repository_urls([
               {"example/app", "https://new.example/app"},
               {"example/db", "https://new.example/db"}
             ])

    assert %Outcome{
             state: %State{cluster: %Cluster{storage: updated}},
             broadcast_opts: [delayed: false, force: true],
             effects: [{:log_entry, %AppendEntry{message_name: :repository_overrides, message_data: {2}}}]
           } =
             ImagesDomain.plan(state, payload) |> Plan.execute()

    assert %{
             "example/app" => "https://new.example/app",
             "example/db" => "https://new.example/db"
           } =
             updated
             |> Images.list()
             |> Map.new(fn %Image{name: name, metadata: metadata} -> {name, metadata.repository_url} end)
  end

  test "delete_lock change updates the in-memory image immediately" do
    locked_image = image(id: "sha256:removable", node: "node_a", settings: %Image.Settings{delete_lock: false})
    storage = NodeStorage.new() |> NodeStorage.put_images("node_a", [locked_image])
    state = %State{cluster: %Cluster{storage: storage}}

    assert {:ok, payload} =
             Mutation.image_delete_lock("node_a", "sha256:removable", true)

    assert %Outcome{
             state: %State{cluster: %Cluster{storage: with_lock}},
             broadcast_opts: [delayed: false, force: true],
             effects: []
           } =
             ImagesDomain.plan(state, payload) |> Plan.execute()

    assert [%Image{settings: %Image.Settings{delete_lock: true}}] = Images.list_node(with_lock, "node_a")
  end

  test "delete_lock change rejects a missing image id" do
    storage = NodeStorage.new() |> NodeStorage.put_images("node_a", [image(id: "sha256:base")])
    state = %State{cluster: %Cluster{storage: storage}}
    assert {:ok, payload} = Mutation.image_delete_lock("node_a", "sha256:missing", true)

    assert {:error, {:image_delete_lock, :image_not_found}} =
             ImagesDomain.plan(state, payload) |> Plan.execute()
  end

  test "reload refreshes imported image metadata and settings" do
    current = image(name: "example/app", id: "sha256:app", locked: false)

    assert {:ok, _metadata} =
             Image.Metadata.default("example/app")
             |> Image.Metadata.set_repository_url("https://imported.example/app")
             |> ImageMetadata.insert("example/app")

    assert {:ok, _settings} =
             %Image.Settings{delete_lock: true}
             |> ImageSettings.insert("node_a", "sha256:app")

    state =
      NodeStorage.new()
      |> NodeStorage.put_images("node_a", [current])
      |> then(&%State{cluster: %Cluster{storage: &1}})

    assert %State{cluster: %Cluster{storage: storage}} = ImagesDomain.reload(state)

    assert [
             %Image{
               metadata: %Image.Metadata{repository_url: "https://imported.example/app"},
               settings: %Image.Settings{delete_lock: true}
             }
           ] = Images.list_node(storage, "node_a")
  end

  defp image(opts) do
    ImageFixture.build(
      Keyword.merge(
        [node: "node_a", id: "sha256:default", tags: [], size: 0, shared_size: 0],
        opts
      )
    )
  end
end
