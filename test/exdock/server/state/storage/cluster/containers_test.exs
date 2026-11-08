defmodule Exdock.Server.State.Storage.ContainersTest do
  use Exdock.DataCase, async: false

  alias Exdock.Server.State
  alias Exdock.Server.State.Domains.Containers, as: ContainersDomain
  alias Exdock.Server.State.Change.{Outcome, Plan}
  alias Exdock.Runtime.Mutation
  alias Exdock.Server.State.Storage.Cluster
  alias Exdock.Server.State.Storage.Containers
  alias Exdock.Server.State.Storage.Images
  alias Exdock.Server.State.Storage.TagsInfo
  alias Exdock.Server.State.Storage.Persistence.ContainerSettings
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage
  alias Exdock.Domain
  alias Exdock.Domain.Container
  alias Exdock.Server.Logging.AppendEntry

  test "container info groups runtime state and counts update priorities" do
    info =
      [
        container("app", true, :outdated, 5, "stack-a"),
        container("worker", true, :updated, 3, "stack-a"),
        container("db", false, :unknown, 2, "stack-b"),
        container("cache", false, :empty_local_digest, 1, "")
      ]
      |> Containers.Info.new()

    assert info.combined.containers_count == 4
    assert info.combined.stacks_count == 2
    assert info.combined.counters.status.outdated == %{count: 1, percentage: 25.0}
    assert info.combined.counters.status.updated == %{count: 1, percentage: 25.0}
    assert info.combined.counters.status.unknown == %{count: 1, percentage: 25.0}
    assert info.combined.counters.status.errored == %{count: 1, percentage: 25.0}
    assert info.combined.counters.priority == %{ignore: 0, low: 0, normal: 0, high: 0, to_update: 1}

    assert info.running.containers_count == 2
    assert info.running.counters.status.outdated == %{count: 1, percentage: 50.0}
    assert info.stopped.containers_count == 2
    assert info.stopped.counters.status.errored == %{count: 1, percentage: 50.0}
  end

  test "container info returns zeroed values for empty input" do
    info = Containers.Info.new([])

    assert info.combined.containers_count == 0
    assert info.combined.stacks_count == 0
    assert info.combined.latest_started_at == nil
    assert info.combined.restarting? == false
    assert info.combined.counters.status.outdated == %{count: 0, percentage: 0}
    assert info.combined.counters.status.updated == %{count: 0, percentage: 0}
    assert info.combined.counters.status.unknown == %{count: 0, percentage: 0}
    assert info.combined.counters.status.errored == %{count: 0, percentage: 0}
    assert info.combined.counters.priority == %{ignore: 0, low: 0, normal: 0, high: 0, to_update: 0}
  end

  test "container info retains the latest running start time without freezing its age" do
    older = ~U[2026-06-30 15:00:00Z]
    newer = ~U[2026-06-30 16:00:00Z]

    info =
      [
        container("older", true, :updated, 3, "stack") |> with_started_at(older),
        container("newer", true, :updated, 3, "stack") |> with_started_at(newer),
        container("stopped", false, :updated, 3, "stack") |> with_started_at(~U[2026-06-30 17:00:00Z])
      ]
      |> Containers.Info.new()

    assert info.combined.latest_started_at == newer
    assert info.running.latest_started_at == newer
    assert info.stopped.latest_started_at == nil
  end

  test "bulk priority changes update each container from the accumulated storage" do
    state =
      state_with_containers([container("app", true, :outdated, 3, "stack"), container("worker", true, :outdated, 3, "stack")])

    assert {:ok, payload} =
             Mutation.container_priorities([{"node", "app", 5}, {"node", "worker", 1}])

    assert %Outcome{
             state: %State{cluster: %Cluster{storage: storage}},
             broadcast_opts: [delayed: false, force: true],
             effects: [
               {:log, :info, "Set container priority: container=app node=node priority=5"},
               {:log, :info, "Set container priority: container=worker node=node priority=1"},
               {:log_entry, %AppendEntry{message_name: :containers_priorities, message_data: {2}}}
             ]
           } =
             ContainersDomain.plan(state, payload) |> Plan.execute()

    priorities =
      storage
      |> Containers.list_node("node")
      |> Map.new(fn %Container{name: name} = container -> {name, Container.priority(container)} end)

    assert priorities == %{"app" => 5, "worker" => 1}
  end

  test "auto update changes update memory and persisted settings" do
    state = state_with_containers([container("app", true, :outdated, 3, "stack")])
    assert {:ok, payload} = Mutation.container_auto_update("node", "app", :enabled)

    assert %Outcome{
             state: %State{cluster: %Cluster{storage: storage}},
             broadcast_opts: [delayed: false, force: true],
             effects: [{:log, :info, "Set container auto_update: container=app node=node auto_update=enabled"}]
           } =
             ContainersDomain.plan(state, payload) |> Plan.execute()

    assert [%Container{core: %Container.Core{settings: %Container.Settings{auto_update: :enabled}}}] =
             Containers.list_node(storage, "node")

    assert %Container.Settings{auto_update: :enabled} = ContainerSettings.load("node", "app")
  end

  test "reload skips containers whose image is missing and keeps valid containers" do
    state =
      [container("app", true, :updated, 3, "stack"), container("orphan", true, :outdated, 3, "stack")]
      |> state_with_containers()
      |> put_images([image("app")])
      |> put_tags([tag_info("example/app:latest", "digest-app"), tag_info("example/orphan:latest", "digest-orphan")])

    assert %State{cluster: %Cluster{storage: storage}} = ContainersDomain.reload(state)

    assert [%Container{name: "app", core: %Container.Core{image_data: %Container.Core.ImageData{status: :updated}}}] =
             Containers.list_node(storage, "node")
  end

  test "reload refreshes imported container settings" do
    assert {:ok, _settings} =
             Container.Settings.default()
             |> Container.Settings.set_priority(5)
             |> ContainerSettings.insert("node", "app")

    state =
      [container("app", true, :updated, 3, "stack")]
      |> state_with_containers()
      |> put_images([image("app")])
      |> put_tags([tag_info("example/app:latest", "digest-app")])

    assert %State{cluster: %Cluster{storage: storage}} =
             ContainersDomain.reload_settings(state)

    assert [%Container{core: %Container.Core{settings: %Container.Settings{priority: 5}}}] =
             Containers.list_node(storage, "node")
  end

  test "retrieve exposes the durable string-keyed container map" do
    app = container("app", true, :updated, 3, "stack")
    state = state_with_containers([app])

    assert %{"node" => [^app]} = Containers.full_string_map(state)
  end

  test "broadcast exposes the durable string-keyed container map" do
    app = container("app", true, :updated, 3, "stack")
    state = state_with_containers([app])

    assert {%{"node" => [^app]}, []} = ContainersDomain.broadcast(state)
  end

  test "set_container updates the in-memory projection without persistence state" do
    current = container("app", true, :updated, 3, "stack")

    storage =
      Cluster.new().storage
      |> NodeStorage.put_containers("node", [current])

    unchanged = Containers.set_container(storage, "node", current)

    assert Containers.list_node(unchanged, "node") == [current]

    changed = %{current | id: "container-app-recreated"}

    changed_storage = Containers.set_container(storage, "node", changed)

    assert Containers.list_node(changed_storage, "node") == [changed]
  end

  defp state_with_containers(containers) do
    node =
      "node"
      |> Domain.Node.default()
      |> Domain.Node.put_metadata(%{"platform" => "linux/amd64"})

    storage =
      Cluster.new().storage
      |> Exdock.Server.State.Storage.Nodes.set("node", node)
      |> Containers.set_node("node", containers)

    %State{cluster: %Cluster{storage: storage}}
  end

  defp put_images(%State{cluster: %Cluster{storage: storage} = cluster} = state, images) do
    %{state | cluster: %{cluster | storage: Images.set_node(storage, "node", images)}}
  end

  defp put_tags(%State{} = state, tags) do
    %{
      state
      | tags: %TagsInfo{
          tags:
            Map.new(tags, fn %Domain.TagInfo{
                               tag: tag,
                               platform: platform
                             } = info ->
              {{tag, platform}, info}
            end)
        }
    }
  end

  defp container(name, running?, image_status, priority, stack_name) do
    %Container{
      node: "node",
      name: name,
      id: "container-#{name}",
      core: %Container.Core{
        is_deleted: false,
        is_running: running?,
        stack_name: stack_name,
        configuration: %Container.Configuration{},
        state: %Container.Core.State{restarting: false},
        image_data: %Container.Core.ImageData{
          status: image_status,
          tag_info: %Domain.TagInfo{
            tag: "example/#{name}:latest",
            platform: "linux/amd64"
          },
          image: image(name)
        },
        settings: Container.Settings.default() |> Container.Settings.set_priority(priority)
      }
    }
  end

  defp with_started_at(%Container{core: core} = container, started_at) do
    %{container | core: %{core | state: %{core.state | started_at: started_at}}}
  end

  defp image(name) do
    %Domain.Image{
      node: "node",
      id: "image-#{name}",
      name: "example/#{name}",
      tags: ["example/#{name}:latest"],
      digest: "digest-#{name}",
      size: 1024,
      shared_size: 128,
      size_human: "1 KB",
      build_date: ~U[2026-06-30 15:43:22Z],
      metadata: Domain.Image.Metadata.default("example/#{name}"),
      registry_url: "example/#{name}",
      in_use: true,
      settings: Domain.Image.Settings.default()
    }
  end

  defp tag_info(tag, digest) do
    Domain.TagInfo.new(
      tag,
      "linux/amd64",
      digest,
      ~U[2026-06-30 15:43:22Z],
      ~U[2026-06-30 16:00:00Z]
    )
  end
end
