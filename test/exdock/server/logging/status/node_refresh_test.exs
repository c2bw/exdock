defmodule Exdock.Server.Logging.Status.NodeRefreshTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Logging.Status
  alias Exdock.Server.Logging.Status.Lifecycle
  alias Exdock.Server.Logging.Status.NodeRefresh.Progress
  alias Exdock.Server.Logging.Status.TrackedJob
  alias Exdock.Server.Jobs.Payload.NodeRefresh, as: NodeRefreshPayload
  alias Exdock.Status.Dashboard.Row

  @now ~U[2026-07-31 10:00:00Z]

  test "progress independently tracks responses and terminal errors" do
    progress = Progress.new(%{}, ["node_a", "node_b"])

    {progress, first} =
      Progress.record_response(progress, "node_a", %{ok: [], errored: []}, nil)

    assert first.message == "waiting for [1] nodes"
    assert Progress.completion(progress) == :pending

    {progress, second} =
      Progress.record_response(
        progress,
        "node_b",
        %{ok: [], errored: []},
        :nodedown
      )

    assert second.message == "nodes: [0] waiting, [1] errored"
    assert Progress.completion(progress) == {:complete, :error}
  end

  test "tracks node responses after initializing a refresh job" do
    status =
      start_status(
        Status.new(),
        :node_refresh,
        "refresh-1",
        ["node_a"],
        NodeRefreshPayload.new(%{"node_a" => []}, nil, [])
      )

    assert %{data: %{waiting_response: 1, wanted_nodes: ["node_a"]}} =
             status.jobs[{:node_refresh, "refresh-1"}]

    updated = update_status(status, :node_refresh, "refresh-1", "node_a", %{ok: [], errored: []}, nil)

    assert %{data: %{waiting_response: 0, wanted_nodes: [], containers_response: %{"node_a" => []}}} =
             updated.jobs[{:node_refresh, "refresh-1"}]
  end

  test "leaves terminal job dispatch to the jobs process" do
    status =
      start_status(
        Status.new(),
        :node_refresh,
        "refresh-1",
        ["node_a"],
        NodeRefreshPayload.new(%{"node_a" => []}, nil, [])
      )

    lifecycle =
      Lifecycle.updated(
        :node_refresh,
        "refresh-1",
        "node_a",
        %{ok: [], errored: []},
        nil,
        @now
      )

    assert {_status, nil, []} =
             Status.update_transition(status, lifecycle)
  end

  test "repairs refresh jobs whose internal data is nil" do
    initial_dash = Status.new().dash

    status = %Status{
      jobs: %{
        {:node_refresh, "refresh-1"} => TrackedJob.new(["node_a"], nil, {:ok, :requested})
      },
      dash: %{initial_dash | node_refresh: %{"node_a" => Row.new({:ok, :requested}, nil)}}
    }

    updated = update_status(status, :node_refresh, "refresh-1", "node_a", %{ok: [], errored: []}, nil)

    assert %{data: data} = updated.jobs[{:node_refresh, "refresh-1"}]
    assert data.waiting_response == 0
    assert data.wanted_nodes == []
    assert data.containers_before == %{}
    assert data.containers_response == %{"node_a" => []}
    assert updated.dash.node_refresh == %{}
  end

  defp start_status(status, job_name, job_id, locations, data) do
    Status.start(status, Lifecycle.started(job_name, job_id, locations, data, @now))
  end

  defp update_status(status, job_name, job_id, node, data, error) do
    lifecycle = Lifecycle.updated(job_name, job_id, node, data, error, @now)
    {status, _log_update, _effects} = Status.update_transition(status, lifecycle)
    status
  end
end
