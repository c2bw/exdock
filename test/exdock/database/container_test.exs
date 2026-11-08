defmodule Exdock.Database.ContainerTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Domain.Container
  alias Exdock.Domain.Container.Core

  setup do
    unless Process.whereis(Exdock.Database.Vault) do
      start_supervised!({Exdock.Database.Vault, name: Exdock.Database.Vault})
    end

    :ok
  end

  test "new/1 preserves distinct container and image ids" do
    attributes = %{
      node: "node",
      name: "example",
      id: "container-id",
      is_deleted: false,
      stack_name: "example",
      configuration: %Container.Configuration{},
      state: %Core.State{},
      is_running: true,
      image_status: :updated,
      image_tag: "example/app:latest",
      image_id: "sha256:image-id"
    }

    assert %Database.Container.Record{
             id: "container-id",
             image_id: "sha256:image-id"
           } = Database.Container.new(attributes)
  end

  test "round-trips string node names" do
    image = database_image()

    container = database_container()

    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(image)
    assert {:ok, %Database.Container.Record{node: "node", name: "example"}} = Database.Container.insert(container)

    assert {:ok, %Database.Container.Record{node: "node", name: "example", image_id: "sha256:image-id"}} =
             Database.Container.load("node", "example")

    assert ["sha256:image-id"] = Database.Container.images_ids("node")
  end

  test "accepts stored string node keys in node query helpers" do
    image = database_image()

    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(image)
    assert {:ok, %Database.Container.Record{}} = database_container(name: "example") |> Database.Container.insert()

    assert {:ok, %Database.Container.Record{}} =
             database_container(name: "example2", image_id: "sha256:image-id", is_deleted: false) |> Database.Container.insert()

    assert {:ok, %Database.Container.Record{node: "node", name: "example", image_id: "sha256:image-id"}} =
             Database.Container.load("node", "example")

    assert {:ok, containers} = Database.Container.load_node("node")

    assert [%Database.Container.Record{name: "example"}, %Database.Container.Record{name: "example2"}] =
             Enum.sort_by(containers, & &1.name)

    assert Database.Container.images_ids("node") == ["sha256:image-id", "sha256:image-id"]

    assert {1, nil} = Database.Container.mark_set("node", ["example"])

    assert {:ok, %Database.Container.Record{name: "example", is_deleted: false}} =
             Database.Container.load("node", "example")

    assert {:ok, %Database.Container.Record{name: "example2", is_deleted: true}} =
             Database.Container.load("node", "example2", true)
  end

  test "rejects invalid stored node keys in node-scoped helpers" do
    assert_raise ArgumentError, fn -> Database.Container.load_node("bad node", false) end
    assert_raise ArgumentError, fn -> Database.Container.load_node("bad node", true) end
    assert_raise ArgumentError, fn -> Database.Container.mark_set("bad node", ["example"]) end
    assert_raise ArgumentError, fn -> Database.Container.images_ids("bad node") end
  end

  test "persists configuration and state in stored format and reloads runtime structs" do
    configuration = %Container.Configuration{
      created: "2026-06-30T15:43:22Z",
      hostname: "example-host",
      env: ["MIX_ENV=prod"],
      ports: %{"4000/tcp" => [%{"HostIp" => "0.0.0.0", "HostPort" => "4000"}]},
      binds: ["/srv/example:/app"]
    }

    state = %Core.State{
      status: "running",
      running: true,
      paused: false,
      pid: 1234,
      started_at: "2026-06-30T15:43:22Z"
    }

    assert {:ok, %Database.Image.Record{}} = database_image() |> Database.Image.insert()

    assert {:ok,
            %Database.Container.Record{node: "node", name: "example", configuration: saved_configuration, state: saved_state}} =
             database_container(configuration: configuration, state: state) |> Database.Container.insert()

    assert saved_configuration["hostname"] == "example-host"
    assert saved_state["status"] == "running"

    stored = Exdock.Repo.get_by!(Database.Container.Row, node: "node", name: "example")

    assert stored.node == "node"
    assert is_binary(stored.configuration)
    assert is_binary(stored.state)
    refute stored.configuration == configuration
    refute stored.state == state

    assert {:ok,
            %Database.Container.Record{
              node: "node",
              configuration: loaded_configuration,
              state: loaded_state
            }} = Database.Container.load("node", "example")

    assert loaded_configuration["hostname"] == "example-host"
    assert loaded_state["status"] == "running"
  end

  test "load helpers exclude deleted containers unless requested" do
    assert {:ok, %Database.Image.Record{}} = database_image() |> Database.Image.insert()
    assert {:ok, %Database.Container.Record{}} = database_container(is_deleted: true) |> Database.Container.insert()

    assert Database.Container.load("node", "example") == {:ok, nil}

    assert {:ok, %Database.Container.Record{name: "example", is_deleted: true}} =
             Database.Container.load("node", "example", true)

    assert Database.Container.load_node("node") == {:ok, []}

    assert {:ok, [%Database.Container.Record{name: "example", is_deleted: true}]} =
             Database.Container.load_node("node", true)

    assert Database.Container.images_ids("node") == []
    assert ["sha256:image-id"] = Database.Container.images_ids("node", true)
  end

  test "reports corrupt persisted payloads without raising or partially decoding a node set" do
    assert {:ok, %Database.Image.Record{}} = database_image() |> Database.Image.insert()
    assert {:ok, %Database.Container.Record{}} = database_container() |> Database.Container.insert()

    Database.Container.Row
    |> Exdock.Repo.get_by!(node: "node", name: "example")
    |> Ecto.Changeset.change(configuration: "not-a-compressed-payload")
    |> Exdock.Repo.update!()

    assert {:error, {:invalid_container_payload, "node", "example", {:configuration, {:gunzip_failed, _message}}}} =
             Database.Container.load("node", "example")

    assert {:error, {:invalid_container_payload, "node", "example", _reason}} =
             Database.Container.load_node("node")
  end

  test "insert/1 rejects containers whose image is not present on the node" do
    container = database_container(name: "orphan", image_id: "sha256:missing-image")

    assert Database.Container.insert(container) == {:error, :empty_image_id}
    assert Database.Container.load("node", "orphan", true) == {:ok, nil}
  end

  test "validates, encrypts, and upserts container batches" do
    assert :ok =
             Database.Image.insert_all([
               database_image(id: "sha256:batch-a"),
               database_image(id: "sha256:batch-b")
             ])

    containers = [
      database_container(name: "batch-a", id: "container-a", image_id: "sha256:batch-a"),
      database_container(name: "batch-b", id: "container-b", image_id: "sha256:batch-b")
    ]

    assert :ok = Database.Container.insert_all(containers)

    assert {:ok, %Database.Container.Record{configuration: %{}, state: %{}}} =
             Database.Container.load("node", "batch-a")

    assert {:error, :empty_image_id} =
             Database.Container.insert_all([
               database_container(name: "orphan-batch", image_id: "sha256:missing")
             ])
  end

  defp database_image(attrs \\ []) do
    attrs = Map.new(attrs)

    %Database.Image.Record{
      node: Map.get(attrs, :node, "node"),
      id: Map.get(attrs, :id, "sha256:image-id"),
      name: Map.get(attrs, :name, "example/app"),
      tags: Map.get(attrs, :tags, ["latest"]),
      digest: Map.get(attrs, :digest, "sha256:digest"),
      size: Map.get(attrs, :size, 1024),
      shared_size: Map.get(attrs, :shared_size, 128),
      build_date: Map.get(attrs, :build_date, ~U[2026-06-30 15:43:22Z])
    }
  end

  defp database_container(attrs \\ []) do
    attrs = Map.new(attrs)
    image_id = Map.get(attrs, :image_id, "sha256:image-id")

    %{
      node: Map.get(attrs, :node, "node"),
      name: Map.get(attrs, :name, "example"),
      id: Map.get(attrs, :id, "container-id"),
      is_deleted: Map.get(attrs, :is_deleted, false),
      stack_name: Map.get(attrs, :stack_name, "example"),
      configuration: Map.get(attrs, :configuration, %Container.Configuration{}),
      state: Map.get(attrs, :state, %Core.State{}),
      is_running: Map.get(attrs, :is_running, true),
      image_status: Map.get(attrs, :image_status, :updated),
      image_tag: Map.get(attrs, :image_tag, "example/app:latest"),
      image_id: image_id
    }
    |> Database.Container.new()
  end
end
