defmodule Exdock.Domain.ContainerTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.Container, as: ContainerPersistence
  alias Exdock.Server.State.Storage.Persistence.ContainerSettings
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Server.State.Storage.Persistence.Error, as: PersistenceError
  alias Exdock.Server.State.Storage.Persistence.LoadReport
  alias Exdock.Server.State.Storage.Persistence.TagInfo, as: TagInfoPersistence
  alias Exdock.Domain
  alias Exdock.Domain.Container
  alias Exdock.Domain.Container.Core
  alias Exdock.Domain.Container.Settings
  alias Exdock.Domain.Node

  setup do
    unless Process.whereis(Exdock.Database.Vault) do
      start_supervised!({Exdock.Database.Vault, name: Exdock.Database.Vault})
    end

    :ok
  end

  test "load/4 rehydrates a persisted container from its joined records" do
    assert :ok = insert_node()
    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(database_image())
    assert {:ok, %Database.ImageTagInfo{}} = TagInfoPersistence.insert(tag_info())
    assert {:ok, %Database.Container.Record{}} = database_container() |> Database.Container.insert()

    assert {:ok, %Container{} = container} =
             ContainerPersistence.load("node", "example", "linux/amd64")

    assert container.node == "node"
    assert container.name == "example"
    assert container.id == "container-id"
    assert %Core{} = container.core
    assert container.core.image_data.image.id == "sha256:image-id"
    assert container.core.image_data.tag_info.tag == "registry.example/app:latest"
    assert container.core.image_data.present_on_node == true
  end

  test "load/4 accepts string node keys" do
    assert :ok = insert_node()
    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(database_image())
    assert {:ok, %Database.ImageTagInfo{}} = TagInfoPersistence.insert(tag_info())
    assert {:ok, %Database.Container.Record{}} = database_container() |> Database.Container.insert()

    assert {:ok, %Container{} = container} =
             ContainerPersistence.load("node", "example", "linux/amd64")

    assert container.node == "node"
    assert container.name == "example"
    assert container.id == "container-id"
  end

  test "load/4 normalizes a persisted null stack name" do
    assert :ok = insert_node()
    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(database_image())
    assert {:ok, %Database.ImageTagInfo{}} = TagInfoPersistence.insert(tag_info())

    container = %{database_container() | stack_name: nil}
    assert {:ok, %Database.Container.Record{}} = Database.Container.insert(container)

    assert {:ok, %Container{core: %Core{stack_name: ""}}} =
             ContainerPersistence.load("node", "example", "linux/amd64")
  end

  test "load/4 reports incomplete joined data without raising" do
    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(database_image())
    assert {:ok, %Database.ImageTagInfo{}} = TagInfoPersistence.insert(tag_info())
    assert {:ok, %Database.Container.Record{}} = database_container() |> Database.Container.insert()

    assert {:error,
            %PersistenceError{
              operation: :container_load,
              cause: {:not_found, :node_data, "node"}
            }} =
             ContainerPersistence.load("node", "example", "linux/amd64")
  end

  test "load_node/3 accepts string node keys" do
    assert :ok = insert_node()
    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(database_image())
    assert {:ok, %Database.ImageTagInfo{}} = TagInfoPersistence.insert(tag_info())
    assert {:ok, %Database.Container.Record{}} = database_container() |> Database.Container.insert()

    assert {:ok, [%Container{node: "node", name: "example"}]} =
             ContainerPersistence.load_node("node", "linux/amd64")
  end

  test "load_node/3 hydrates a container batch from shared node context" do
    assert :ok = insert_node()
    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(database_image())
    assert {:ok, %Database.ImageTagInfo{}} = TagInfoPersistence.insert(tag_info())

    app = database_container()
    worker = %{database_container() | name: "worker", id: "worker-id"}

    assert :ok = Database.Container.insert_all([app, worker])

    assert {:ok, %Database.ContainerSettings{}} =
             %Settings{priority: 5, auto_update: :enabled, labels: ["worker"]}
             |> ContainerSettings.insert("node", "worker")

    assert {:ok, loaded_containers} =
             ContainerPersistence.load_node("node", "linux/amd64")

    containers = Map.new(loaded_containers, &{&1.name, &1})

    assert %Container{core: %Core{settings: %Settings{priority: 3}}} = containers["example"]

    assert %Container{
             id: "worker-id",
             core: %Core{settings: %Settings{priority: 5, auto_update: :enabled}}
           } = containers["worker"]
  end

  test "load_node/3 reports every hydration failure without hiding valid rows" do
    assert :ok = insert_node()
    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(database_image())
    assert {:ok, %Database.ImageTagInfo{}} = TagInfoPersistence.insert(tag_info())

    valid = database_container()

    missing_tag = %{
      database_container()
      | name: "missing-tag",
        id: "missing-tag-id",
        image_tag: "registry.example/missing:latest"
    }

    assert :ok = Database.Container.insert_all([valid, missing_tag])

    assert {:error,
            %LoadReport{
              operation: :container_load,
              values: [%Container{name: "example"}],
              failures: [
                %PersistenceError{
                  cause: {:not_found, :tag_info, %{container: "missing-tag"}}
                }
              ]
            }} = ContainerPersistence.load_node("node", "linux/amd64")
  end

  defp insert_node do
    "node"
    |> Node.default()
    |> Node.set_fetched_at(DateTime.utc_now())
    |> NodePersistence.insert()
  end

  defp database_image do
    %Database.Image.Record{
      node: "node",
      id: "sha256:image-id",
      name: "registry.example/app",
      tags: ["registry.example/app:latest"],
      digest: "sha256:digest",
      size: 1024,
      shared_size: 128,
      build_date: ~U[2026-06-30 15:43:22Z]
    }
  end

  defp tag_info do
    Domain.TagInfo.new(
      "registry.example/app:latest",
      "linux/amd64",
      "sha256:digest",
      ~U[2026-06-30 15:43:22Z],
      ~U[2026-06-30 16:00:00Z]
    )
  end

  defp database_container do
    %Database.Container.Record{
      node: "node",
      name: "example",
      id: "container-id",
      is_running: true,
      stack_name: "example",
      configuration: %Container.Configuration{},
      state: %Core.State{},
      image_tag: "registry.example/app:latest",
      image_id: "sha256:image-id",
      image_status: :updated,
      is_deleted: false
    }
  end
end
