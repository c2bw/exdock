defmodule Exdock.Server.Logging.StatusTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Logging.Status
  alias Exdock.Server.Logging.Status.{Lifecycle, TrackedJob, Utils}
  alias Exdock.Server.Jobs.Payload.{ContainerAction, ImageAction, RegistryFetch}
  alias Exdock.Status.Dashboard.Row

  @now ~U[2026-07-31 10:00:00Z]

  test "add stores normalized job data and creates one dash row per location" do
    status =
      %Status{}
      |> start_status(
        :image_pull,
        "job-1",
        [:node_a, :node_b],
        %ImageAction{node: nil, image_tag: "example/app:latest"}
      )

    assert %{
             {:image_pull, "job-1"} => %{
               locations: [:node_a, :node_b],
               data: "example/app:latest",
               state: {:ok, :requested}
             }
           } = status.jobs

    assert status.dash.image_pull == %{
             {:node_a, "example/app:latest"} => Row.new({:ok, :requested}, nil),
             {:node_b, "example/app:latest"} => Row.new({:ok, :requested}, nil)
           }
  end

  test "update_job_message mirrors progress text into supported dash rows" do
    status =
      %Status{}
      |> start_status(
        :image_pull,
        "job-1",
        [:node_a],
        %ImageAction{node: :node_a, image_tag: "example/app:latest"}
      )
      |> Status.update_job_message(:image_pull, "job-1", :node_a, "Downloading layer")

    assert %{
             {:node_a, "example/app:latest"} => %{
               state: {:ok, :requested},
               data: nil,
               message: "Downloading layer"
             }
           } = status.dash.image_pull
  end

  test "successful recreation retains an actionable cleanup warning without failing the job" do
    warning = "Container [app] was recreated, but cleanup of [app-exdock-old-123] failed: permission denied"

    status =
      start_status(Status.new(), :container_recreate, "recreate-1", [:node_a], %ContainerAction{node: :node_a, container: "app"})

    lifecycle =
      Lifecycle.finished(:container_recreate, "recreate-1", :node_a, %{"container" => "app", "warning" => warning}, nil, @now)

    assert {completed, {"recreate-1", :finished, _opts}, []} = Status.result_transition(status, lifecycle)
    assert completed.jobs == %{}
    assert completed.dash.container_recreate[{:node_a, "app"}].state == {:warning, warning}
    assert completed.dash.container_recreate[{:node_a, "app"}].message == {:string, warning}
    assert completed.latest_job_message =~ warning
    assert [{_time, "Warning: " <> ^warning}] = completed.errors
    assert Status.has_errors?(completed)
    assert Exdock.ReadModel.Status.errors?(completed)
    assert Status.clear_errors(completed).dash.container_recreate == %{}
  end

  test "detects errored dash entries" do
    status = %Status{
      dash: %{
        container_start: %{
          {:node, "app"} => Row.new({:ok, :requested}, nil)
        },
        image_pull: %{
          {:node, "example/app:latest"} => Row.new({:error, :nodedown}, nil)
        }
      }
    }

    assert Status.has_errors?(status)
  end

  test "clears only errored dash entries" do
    status = %Status{
      dash: %{
        container_start: %{
          {:node, "app"} => Row.new({:ok, :requested}, nil),
          {:node, "db"} => Row.new({:error, :failed}, nil)
        }
      }
    }

    cleared = Status.clear_errors(status)

    refute Status.has_errors?(cleared)
    assert Map.has_key?(cleared.dash.container_start, {:node, "app"})
    refute Map.has_key?(cleared.dash.container_start, {:node, "db"})
  end

  test "counts active lifecycle jobs independently of dash rows" do
    status = %Status{
      jobs: %{
        {:container_start, "job-1"} => TrackedJob.new([:node_a], nil, {:ok, :requested}),
        {:node_refresh, "job-2"} => TrackedJob.new([:node_a, :node_b], nil, {:ok, :requested})
      }
    }

    assert Status.count_active_jobs(status) == 2
  end

  test "ignores updates and results for jobs that are no longer tracked" do
    status = %Status{}

    assert update_status(status, :node_refresh, "stale-job", :node_a, %{ok: [], errored: []}, nil) == status
    assert finish_status(status, :node_refresh, "stale-job", :node_a, nil, nil) == status
  end

  test "container log results display the tracked container name instead of its Docker id" do
    status =
      %Status{}
      |> start_status(:container_logs, "logs-1", [:node_a], ContainerAction.new("node_a", "paperless"))
      |> finish_status(:container_logs, "logs-1", :node_a, "5e822a2760aac4c9cff09329e8e22ee92", nil)

    assert status.latest_job == "Container Logs"
    assert status.latest_job_message == "OK: [paperless] on [node_a]"
  end

  test "container lifecycle variants share one status handler without losing their labels" do
    for {job_name, label} <- [
          container_start: "Start Container",
          container_stop: "Stop Container",
          container_restart: "Restart Container"
        ] do
      status =
        %Status{}
        |> start_status(job_name, "job-1", [:node_a], %ContainerAction{
          node: :node_a,
          container: "paperless"
        })
        |> finish_status(job_name, "job-1", :node_a, "paperless", nil)

      assert status.latest_job == label
      assert status.latest_job_message == "OK: [paperless] on [node_a]"
    end
  end

  test "container recreation mirrors queued progress and handles completion" do
    status =
      Status.new()
      |> start_status(:container_recreate, "recreate-1", [:node_a], %ContainerAction{
        node: :node_a,
        container: "paperless"
      })
      |> Status.update_job_message(:container_recreate, "recreate-1", :node_a, "Pulling image")

    assert status.latest_job == "Recreate Container"
    assert status.latest_job_message == "recreating [paperless] on [:node_a]"
    assert status.dash.container_recreate[{:node_a, "paperless"}].message == "Pulling image"

    completed = finish_status(status, :container_recreate, "recreate-1", :node_a, "paperless", nil)
    assert completed.latest_job_message == "OK: [paperless] on [node_a]"
    assert completed.dash.container_recreate == %{}
  end

  test "registry fetch lifecycle tracks requests through successful completion" do
    requests = [
      %{tag: "example/app:latest", platform: "linux/amd64"},
      %{tag: "example/db:latest", platform: "linux/amd64"}
    ]

    payload = RegistryFetch.new(requests)
    status = start_status(Status.new(), :registry_fetch, "registry-1", [:local], payload)

    assert status.latest_job_message == "0 of 2 images processed"
    assert Status.log(:registry_fetch, payload) == {2, []}
    assert status.dash.registry_fetch["registry-1"].data == %{fetched: 0, total: 2}

    status = update_status(status, :registry_fetch, "registry-1", :local, "example/app:latest", nil)
    assert status.latest_job_message == "1 of 2 images processed"

    completed = finish_status(status, :registry_fetch, "registry-1", :local, :done, nil)
    assert completed.latest_job_message == "OK"
    assert completed.dash.registry_fetch == %{}
  end

  test "failed results without payload use the tracked job data" do
    status =
      %Status{}
      |> start_status(:image_delete, "delete-1", [:node_a], %ImageAction{
        image_id: "sha256:1234567890abcdef",
        image_tags: [],
        node: :node_a
      })
      |> finish_status(:image_delete, "delete-1", :node_a, nil, "node disconnected")

    assert status.latest_job_message ==
             "[sha256:1234567890abcdef] on [node_a]: \"node disconnected\""

    assert [{_timestamp, "delete image [node_a, 1234567890..]: \"node disconnected\""}] =
             status.errors
  end

  test "status utils update tracked job messages without creating missing entries" do
    status =
      Utils.set_job_data(
        %Status{},
        :image_pull,
        "job-1",
        TrackedJob.new([:node_a], "example/app:latest", {:ok, :requested})
        |> TrackedJob.put_message("Queued")
      )

    assert Utils.get_job_data(status, :image_pull, "job-1").message == "Queued"

    status = Utils.set_job_data_message(status, :image_pull, "job-1", "Pulling")
    assert Utils.get_job_data(status, :image_pull, "job-1").message == "Pulling"

    assert status == Utils.set_job_data_message(status, :image_pull, "missing", "Ignored")
  end

  test "status utils split dotted sub-job ids" do
    assert Utils.split_job_id(nil) == {nil, nil}
    assert Utils.split_job_id("parent") == {"parent", nil}
    assert Utils.split_job_id("parent.child") == {"parent", "parent.child"}
    assert Utils.strip_sub_job_from_id("parent.child") == "parent"
    assert Utils.subjob?("parent.child")
    refute Utils.subjob?("parent")
  end

  defp start_status(status, job_name, job_id, locations, data) do
    Status.start(status, Lifecycle.started(job_name, job_id, locations, data, @now))
  end

  defp update_status(status, job_name, job_id, node, data, error) do
    lifecycle = Lifecycle.updated(job_name, job_id, node, data, error, @now)
    {status, _log_update, _effects} = Status.update_transition(status, lifecycle)
    status
  end

  defp finish_status(status, job_name, job_id, node, data, error) do
    lifecycle = Lifecycle.finished(job_name, job_id, node, data, error, @now)
    {status, _log_update, _effects} = Status.result_transition(status, lifecycle)
    status
  end
end
