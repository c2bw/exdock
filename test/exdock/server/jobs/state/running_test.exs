defmodule Exdock.Server.Jobs.State.RunningTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.State.Running

  test "find_job matches equivalent running remote jobs regardless of node order" do
    existing = remote_job(["node_a", "node_b"], [:same]) |> Jobs.Job.set_running()
    candidate = remote_job(["node_b", "node_a"], [:same])
    different_nodes = remote_job(["node_a"], [:same])

    running = Running.new() |> Running.add(existing)

    existing_id = existing.id
    assert {^existing_id, ^existing} = Running.find_job(running, candidate)
    assert Running.find_job_id(running, candidate) == existing_id
    assert Running.find_job_id(running, different_nodes) == nil
  end

  test "find_job ignores local jobs and non-running remote jobs" do
    local = local_job() |> Jobs.Job.set_running()
    terminated_remote = remote_job(["node_a"], [:same]) |> Jobs.Job.set_status(:terminated)
    candidate = remote_job(["node_a"], [:same])

    running =
      Running.new()
      |> Running.add(local)
      |> Running.add(terminated_remote)

    assert Running.find_job(running, candidate) == nil
    assert Running.find_job(running, local_job()) == nil
  end

  test "clean removes terminated local and remote jobs" do
    local = local_job() |> Jobs.Job.set_status(:terminated)
    remote = remote_job(["node_a"], []) |> Jobs.Job.set_status(:terminated)
    active = remote_job(["node_b"], [:active]) |> Jobs.Job.set_running()

    running =
      Running.new()
      |> Running.add(local)
      |> Running.add(remote)
      |> Running.add(active)
      |> Running.clean()

    assert Running.get(running, local.id) == nil
    assert Running.get(running, remote.id) == nil
    assert Running.get(running, active.id) == active
  end

  test "remove_node ignores informational updates, local jobs, and missing jobs" do
    local = local_job() |> Jobs.Job.set_running()

    running =
      Running.new()
      |> Running.add(local)
      |> Running.remove_node(local.id, nil)
      |> Running.remove_node(local.id, "node_a")
      |> Running.remove_node("missing", "node_a")

    assert Running.get(running, local.id) == local
  end

  test "adding an existing id replaces the previous job" do
    local = local_job() |> Jobs.Job.set_running()
    remote = remote_job(["node_a"], []) |> Jobs.Job.set_running()
    same_id = "shared-job-id"

    local = %{local | id: same_id}
    remote = %{remote | id: same_id}

    running =
      Running.new()
      |> Running.add(local)
      |> Running.add(remote)

    assert Running.get(running, same_id) == remote
    assert Running.get_local(running, same_id) == nil
    assert Running.get_remote(running, same_id) == remote
  end

  test "clean evaluates the current value for each job id" do
    local = local_job() |> Jobs.Job.set_status(:terminated)
    remote = remote_job(["node_a"], []) |> Jobs.Job.set_running()
    same_id = "shared-job-id"

    local = %{local | id: same_id}
    remote = %{remote | id: same_id}

    running = Running.new() |> Running.add(local) |> Running.add(remote) |> Running.clean()

    assert Running.get(running, same_id) == remote
  end

  test "remove_node removes only the reporting node from a remote job" do
    remote = remote_job(["node_a", "node_b"], []) |> Jobs.Job.set_running()

    running =
      Running.new()
      |> Running.add(remote)
      |> Running.remove_node(remote.id, "node_a")

    assert %Jobs.Job{type: %Jobs.Job.Remote{nodes: ["node_b"]}} = Running.get_remote(running, remote.id)
  end

  test "result removes reporting node and cleans terminated jobs" do
    finished = remote_job(["node_a", "node_b"], []) |> Jobs.Job.set_status(:terminated)
    active = remote_job(["node_c"], [:active]) |> Jobs.Job.set_running()

    running =
      Running.new()
      |> Running.add(finished)
      |> Running.add(active)
      |> Running.result(Jobs.Result.new(finished.id, "node_a", nil))

    assert Running.get(running, finished.id) == nil
    assert Running.get(running, active.id) == active
  end

  test "result keeps a remote job until its final node reports" do
    remote = remote_job(["node_a", "node_b"], []) |> Jobs.Job.set_running()

    running =
      Running.new()
      |> Running.add(remote)
      |> Running.result(Jobs.Result.new(remote.id, "node_a", nil))

    assert %Jobs.Job{type: %Jobs.Job.Remote{nodes: ["node_b"]}} = Running.get_remote(running, remote.id)

    running = Running.result(running, Jobs.Result.new(remote.id, "node_b", nil))

    assert Running.get_remote(running, remote.id) == nil
  end

  test "result removes a completed local job" do
    local = local_job() |> Jobs.Job.set_running()

    running =
      Running.new()
      |> Running.add(local)
      |> Running.result(Jobs.Result.new(local.id, nil, :done))

    assert Running.get_local(running, local.id) == nil
  end

  defp local_job do
    spec = Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil)
    Jobs.Job.new(detail(:local), spec)
  end

  defp remote_job(nodes, parameters) do
    spec = Jobs.Spec.new(Jobs.Spec.Remote.new(nodes), parameters, nil)
    Jobs.Job.new(detail(:remote), spec)
  end

  defp detail(name), do: Jobs.Detail.new(name, Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil))
end
