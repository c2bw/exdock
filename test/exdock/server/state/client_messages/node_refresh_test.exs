defmodule Exdock.Server.State.ClientMessages.NodeRefreshTest do
  use Exdock.Server.State.ClientMessagesCase, async: false

  alias Exdock.Database
  alias Exdock.Protocol.Messages
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.{Job, Result}
  alias Exdock.Server.Jobs.NodeRefreshSnapshot
  alias Exdock.Server.State.ClientMessages
  alias Exdock.Server.State.ClientMessages.NodeRefresh.Prepared
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster.{Reconciliation, SnapshotCommit}
  alias Exdock.Server.State.Storage.Containers
  alias Exdock.Domain.Container

  @fetched_at ~U[2026-07-31 10:00:00Z]

  test "refresh with an unused dangling image completes successfully and persists it" do
    id = "sha256:5076540d8e7eac46b6af2e4b5473dd527bfdf9a20b559871efbb24df9650ada9"

    source = %DockerEngineAPI.Model.ImageInspect{
      Id: id,
      RepoTags: ["<none>:<none>"],
      RepoDigests: [""],
      Size: 1024,
      Created: 0
    }

    assert {:ok, image} = Exdock.ClientLib.Image.SnapshotMapper.map(source, 0)

    message = %Messages.JobResult{
      job: %Job{id: "refresh-dangling", name: :node_refresh},
      result: %Result{node: "node", data: {%{ok: [], errored: []}, %{ok: [image], errored: []}}, error: nil}
    }

    updated = commit_client_message(base_state(), message)

    assert_receive {:captured, {:job_update, %Jobs.Update{id: "refresh-dangling", error: nil, remove_node: true}}}
    assert [%{id: ^id, tags: [], in_use: false, registry_url: ""}] = Storage.Images.list_node(updated.cluster.storage, "node")
    assert %Database.Image.Record{tags: [], name: ^id} = Database.Image.by_node_and_id("node", id)
  end

  test "initial refresh persists a running container backed by an untagged local image" do
    id = "sha256:" <> String.duplicate("a", 64)

    image = %DockerEngineAPI.Model.ImageInspect{
      RepoTags: [],
      RepoDigests: [],
      Id: id,
      Size: 1024,
      Created: "2026-01-01T00:00:00Z"
    }

    assert {:ok, image} = Exdock.ClientLib.Image.SnapshotMapper.map(image, 0)
    container = %{container_result() | image_id: id, image_tag: id}

    message = %Messages.JobResult{
      job: %Job{id: "refresh-local", name: :node_refresh},
      result: %Result{node: "node", data: {%{ok: [container], errored: []}, %{ok: [image], errored: []}}, error: nil}
    }

    updated = commit_client_message(base_state(), message)
    assert [%Container{id: "container-id"} = stored] = Containers.list_node(updated.cluster.storage, "node")
    assert Container.running?(stored)

    assert [%{id: ^id, tags: [], in_use: true, registry_url: "", metadata: %{repository_url: ""}}] =
             Storage.Images.list_node(updated.cluster.storage, "node")

    assert Storage.Images.repositories_urls(updated.cluster.storage) == []
    assert %Database.Image.Record{tags: [], name: ^id} = Database.Image.by_node_and_id("node", id)
    assert {:ok, reloaded} = Storage.Cluster.load(Storage.Cluster.new(), "node", %{"platform" => "linux/amd64"})
    assert [%Container{id: "container-id"}] = Containers.list_node(reloaded.storage, "node")
    assert [%{id: ^id, tags: [], in_use: true, registry_url: ""}] = Storage.Images.list_node(reloaded.storage, "node")
  end

  test "refresh persists and reloads all repository digests for shared image IDs" do
    references = ["example/first@sha256:first", "example/second@sha256:second"]

    image = %DockerEngineAPI.Model.ImageInspect{
      RepoTags: ["example/first:latest", "example/second:latest"],
      RepoDigests: references,
      Id: "sha256:image-id",
      Size: 1024,
      Created: "2026-01-01T00:00:00Z"
    }

    assert {:ok, image} = Exdock.ClientLib.Image.SnapshotMapper.map(image, 0)
    container = %{container_result() | image_tag: "example/second:latest"}

    message = %Messages.JobResult{
      job: %Job{id: "refresh-multiple", name: :node_refresh},
      result: %Result{node: "node", data: {%{ok: [container], errored: []}, %{ok: [image], errored: []}}, error: nil}
    }

    updated = commit_client_message(base_state(), message)
    assert %Database.Image.Record{repo_digests: ^references} = Database.Image.by_node_and_id("node", image.id)
    assert {:ok, reloaded} = Storage.Cluster.load(Storage.Cluster.new(), "node", %{"platform" => "linux/amd64"})
    tag = Exdock.Domain.TagInfo.new("example/second:latest", "linux/amd64", "sha256:second", @fetched_at, @fetched_at)

    for cluster <- [updated.cluster, reloaded] do
      assert [stored] = Storage.Images.list_node(cluster.storage, "node")
      assert stored.repo_digests == references
      assert Exdock.Domain.Container.Core.ImageData.new(tag, stored, true).status == :updated
      context = Storage.Containers.ImageContext.new(cluster.storage, "node")
      assert Storage.Containers.ImageContext.digest_present?(context, tag)
    end
  end

  test "updates node snapshot on successful node refresh result" do
    state = base_state()

    message = %Messages.JobResult{
      job: %Job{id: "refresh-id", name: :node_refresh},
      result: %Result{
        node: "node",
        data: {container_result_set(), image_result_set()},
        error: nil
      }
    }

    updated = commit_client_message(state, message)

    assert_receive {:captured,
                    {:job_update,
                     %Jobs.Update{
                       update: %NodeRefreshSnapshot{} = refresh_snapshot,
                       remove_node: true,
                       error: nil
                     }}}

    assert %{ok: [container_from_update = %{id: "container-id"}], errored: []} =
             refresh_snapshot.container_results

    assert [%Container{id: "container-id"}] = Containers.list_node(updated.cluster.storage, "node")
    assert container_from_update.id == "container-id"

    assert %Database.Nodes{node: "node"} = Database.Nodes.load("node")

    assert %Database.Image.Record{id: "sha256:image-id"} =
             Database.Image.by_node_and_id("node", "sha256:image-id")

    assert {:ok, %Database.Container.Record{id: "container-id"}} =
             Database.Container.load("node", "app")

    assert {:ok, reloaded_cluster} =
             Storage.Cluster.load(
               Storage.Cluster.new(),
               "node",
               %{"platform" => "linux/amd64"}
             )

    assert [%Container{id: "container-id"} = reloaded_container] =
             Containers.list_node(reloaded_cluster.storage, "node")

    assert %DateTime{} = reloaded_container.core.state.started_at
    assert Container.running?(reloaded_container)
    refute Map.has_key?(reloaded_cluster.storage, :commits)

    writes_before_identical_refresh = sqlite_total_changes()
    identically_refreshed = commit_client_message(updated, message)

    assert sqlite_total_changes() == writes_before_identical_refresh

    assert [%Container{id: "container-id"}] =
             Containers.list_node(identically_refreshed.cluster.storage, "node")

    writes_before_new_health_probe = sqlite_total_changes()

    health_probe_message =
      node_refresh_message(container_result("container-id", ~U[2026-07-21 10:45:00Z]))

    health_refreshed = commit_client_message(identically_refreshed, health_probe_message)

    assert sqlite_total_changes() == writes_before_new_health_probe

    assert [%Container{id: "container-id"}] =
             Containers.list_node(health_refreshed.cluster.storage, "node")
  end

  test "reconciliation remains in memory until the snapshot commit boundary executes" do
    state = base_state()

    message = node_refresh_message(container_result())

    assert %Prepared{updated_state: prepared_state} =
             prepared = ClientMessages.reduce(state, message, @fetched_at)

    assert [%Container{id: "container-id"}] =
             Containers.list_node(prepared_state.cluster.storage, "node")

    assert Database.Nodes.load("node") == nil
    assert Database.Image.by_node_and_id("node", "sha256:image-id") == nil
    assert Database.Container.load("node", "app") == {:ok, nil}

    assert {committed_state, _effects} = Prepared.execute(prepared)

    assert [%Container{id: "container-id"}] =
             Containers.list_node(committed_state.cluster.storage, "node")

    assert %Database.Nodes{node: "node"} = Database.Nodes.load("node")
  end

  test "snapshot reconciliation itself remains free of persistence" do
    state = base_state()

    reconciled =
      Reconciliation.reconcile(
        state.cluster,
        "node",
        [container_result()],
        [client_image()],
        state.tags,
        @fetched_at
      )

    assert [%Container{id: "container-id"}] = Containers.list_node(reconciled.storage, "node")
    assert Database.Nodes.load("node") == nil
    assert Database.Image.by_node_and_id("node", "sha256:image-id") == nil
    assert Database.Container.load("node", "app") == {:ok, nil}

    assert {:ok, committed} =
             SnapshotCommit.commit(
               state.cluster,
               "node",
               [container_result()],
               [client_image()],
               state.tags,
               @fetched_at
             )

    assert [%Container{id: "container-id"}] = Containers.list_node(committed.storage, "node")

    assert %Database.Nodes{node: "node"} = Database.Nodes.load("node")

    assert %Database.Image.Record{id: "sha256:image-id"} =
             Database.Image.by_node_and_id("node", "sha256:image-id")

    assert {:ok, %Database.Container.Record{id: "container-id"}} =
             Database.Container.load("node", "app")
  end

  test "persistence synchronizes records removed by reconciliation" do
    state = base_state()
    populated = commit_client_message(state, node_refresh_message(container_result()))
    removed = commit_client_message(populated, empty_node_refresh_message())

    assert Containers.list_node(removed.cluster.storage, "node") == []
    assert Database.Image.by_node_and_id("node", "sha256:image-id") == nil
    assert Database.Container.load("node", "app") == {:ok, nil}
  end

  test "partial inspection failures preserve known objects and their durable live records" do
    populated = commit_client_message(base_state(), node_refresh_message(container_result()))
    [original] = Containers.list_node(populated.cluster.storage, "node")
    original = %{original | core: %{original.core | settings: %{original.core.settings | priority: 1}}}
    storage = Containers.set_container(populated.cluster.storage, "node", original)
    populated = %{populated | cluster: %{populated.cluster | storage: storage}}

    partial = %Messages.JobResult{
      job: %Job{id: "partial", name: :node_refresh},
      result:
        Result.new(
          "partial",
          "node",
          {%{ok: [], errored: [{:timeout, container_result()}]}, %{ok: [], errored: [{:timeout, "sha256:image-id"}]}}
        )
    }

    updated = commit_client_message(populated, partial)
    assert [^original] = Containers.list_node(updated.cluster.storage, "node")
    assert_receive {:captured, {:job_update, %Jobs.Update{id: "partial", error: :partial_refresh, remove_node: true}}}
    assert %Database.Image.Record{} = Database.Image.by_node_and_id("node", "sha256:image-id")
    assert {:ok, %Database.Container.Record{id: "container-id", is_deleted: false}} = Database.Container.load("node", "app")
    assert [%{in_use: true}] = Storage.Images.list_node(updated.cluster.storage, "node")

    recovered = commit_client_message(updated, node_refresh_message(container_result()))
    assert [%{core: %{settings: %{priority: 1}}}] = Containers.list_node(recovered.cluster.storage, "node")
    removed = commit_client_message(recovered, empty_node_refresh_message())
    assert Containers.list_node(removed.cluster.storage, "node") == []
  end

  test "a failed container inspect keeps its image even when it is absent from successful image results" do
    populated = commit_client_message(base_state(), node_refresh_message(container_result()))
    message = node_refresh_message(container_result())

    message = %{
      message
      | result: %{message.result | data: {%{ok: [], errored: [{:timeout, container_result()}]}, %{ok: [], errored: []}}}
    }

    updated = commit_client_message(populated, message)
    assert [%{id: "container-id"}] = Containers.list_node(updated.cluster.storage, "node")
    assert [%{id: "sha256:image-id", in_use: true}] = Storage.Images.list_node(updated.cluster.storage, "node")
  end

  test "successful containers remain visible when their image inspect fails" do
    populated = commit_client_message(base_state(), node_refresh_message(container_result()))
    message = node_refresh_message(container_result("replacement"))

    message = %{
      message
      | result: %{
          message.result
          | data: {container_result_set_for("replacement"), %{ok: [], errored: [{:timeout, client_image()}]}}
        }
    }

    updated = commit_client_message(populated, message)
    assert [%{id: "replacement"}] = Containers.list_node(updated.cluster.storage, "node")
    assert [%{id: "sha256:image-id", in_use: true}] = Storage.Images.list_node(updated.cluster.storage, "node")
  end

  test "unknown errored objects do not resurrect unrelated missing containers" do
    populated = commit_client_message(base_state(), node_refresh_message(container_result()))
    unknown = %{container_result("unknown") | name: "unknown"}
    message = node_refresh_message(unknown)
    message = %{message | result: %{message.result | data: {%{ok: [], errored: [{:timeout, unknown}]}, image_result_set()}}}
    updated = commit_client_message(populated, message)
    assert Containers.list_node(updated.cluster.storage, "node") == []
  end

  test "late or duplicate refresh generations complete without replacing newer accepted state" do
    old = with_generation(node_refresh_message(container_result("old")), 1, "old-refresh")
    new = with_generation(node_refresh_message(container_result("new")), 2, "new-refresh")
    state = commit_client_message(base_state(), new)
    writes = sqlite_total_changes()

    assert commit_client_message(state, old) == state
    assert commit_client_message(state, new) == state
    assert sqlite_total_changes() == writes
    assert [%{id: "new"}] = Containers.list_node(state.cluster.storage, "node")
    assert {:ok, %Database.Container.Record{id: "new"}} = Database.Container.load("node", "app")
    assert_receive {:captured, {:job_update, %Jobs.Update{id: "old-refresh", remove_node: true}}}
    assert state.refresh_generations == %{"node" => 2}
  end

  test "each node keeps an independent refresh generation" do
    state = %{base_state() | refresh_generations: %{"other-node" => 100}}
    message = with_generation(node_refresh_message(container_result()), 1, "node-refresh")
    updated = commit_client_message(state, message)
    assert updated.refresh_generations == %{"other-node" => 100, "node" => 1}
    assert [%{id: "container-id"}] = Containers.list_node(updated.cluster.storage, "node")
  end

  defp with_generation(message, generation, id) do
    %{message | job: %{message.job | id: id, refresh_generation: generation}, result: %{message.result | id: id}}
  end

  defp container_result_set_for(id), do: %{ok: [container_result(id)], errored: []}

  test "emits errored node refresh update without mutating cluster state" do
    state = state_with_container()

    result = %Result{
      node: "node",
      data: {%{ok: [], errored: []}, %{ok: [], errored: []}},
      error: :nodedown
    }

    message = %Messages.JobResult{
      job: %Job{id: "refresh-id", name: :node_refresh},
      result: result
    }

    updated = commit_client_message(state, message)

    assert_receive {:captured, {:job_update, %Jobs.Update{update: %{}, error: :nodedown, remove_node: true}}}

    assert updated == state
  end
end
