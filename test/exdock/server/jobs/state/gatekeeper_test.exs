defmodule Exdock.Server.Jobs.State.GatekeeperTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.State

  test "links duplicate running remote mutating jobs" do
    existing = remote_job(:container_recreate, ["node_a"], ["app"]) |> Jobs.Job.set_running()
    duplicate = remote_job(:container_recreate, ["node_a"], ["app"])

    state = %State{running: State.Running.new() |> State.Running.add(existing)}

    assert %Jobs.Job{status: :linked} = State.Gatekeeper.job(state.running, duplicate)
  end

  test "links configured remote image mutations" do
    existing = remote_job(:image_pull, ["node_a"], ["alpine:latest"]) |> Jobs.Job.set_running()
    duplicate = remote_job(:image_pull, ["node_a"], ["alpine:latest"])

    state = %State{running: State.Running.new() |> State.Running.add(existing)}

    assert %Jobs.Job{status: :linked} = State.Gatekeeper.job(state.running, duplicate)
  end

  test "does not coalesce mutations across conflicting work for the same container" do
    stop = remote_job(:container_stop, ["node_a"], ["app"]) |> Jobs.Job.set_running()
    start = remote_job(:container_start, ["node_a"], ["app"]) |> Jobs.Job.set_running()
    running = State.Running.new() |> State.Running.add(stop) |> State.Running.add(start)
    final_stop = remote_job(:container_stop, ["node_a"], ["app"])
    assert State.Gatekeeper.job(running, final_stop) == final_stop
  end

  test "preserves every conflicting command in stop start stop dispatch order" do
    spec = Jobs.Spec.new(Jobs.Spec.Remote.new(["node_a"]), ["app"], nil)
    first = Jobs.Detail.new(:container_stop, spec)
    middle = Jobs.Detail.new(:container_start, spec)
    last = Jobs.Detail.new(:container_stop, spec)
    {state, _} = State.transition(State.new(), {:add, first})
    {state, _} = State.transition(state, {:add, middle})
    {state, effects} = State.transition(state, {:add, last})
    assert Enum.any?(effects, &match?({:start_remote, "node_a", %{id: id}} when id == last.id, &1))
    assert State.Linked.get_linked(state.linked_id, first.id) == []
  end

  test "keeps configured remote mutations independent without equivalent running work" do
    existing = remote_job(:container_recreate, ["node_a"], ["app"]) |> Jobs.Job.set_running()
    different_target = remote_job(:container_recreate, ["node_a"], ["worker"])

    state = %State{running: State.Running.new() |> State.Running.add(existing)}

    assert State.Gatekeeper.job(state.running, different_target) == different_target
  end

  test "keeps non-mutating remote jobs independent" do
    existing = remote_job(:node_refresh, ["node_a"], []) |> Jobs.Job.set_running()
    duplicate = remote_job(:node_refresh, ["node_a"], [])

    state = %State{running: State.Running.new() |> State.Running.add(existing)}

    assert State.Gatekeeper.job(state.running, duplicate) == duplicate
  end

  test "keeps local jobs independent even when names match a mutating remote policy" do
    state = %State{running: State.Running.new()}
    job = local_job(:container_recreate)

    assert State.Gatekeeper.job(state.running, job) == job
  end

  defp remote_job(name, nodes, parameters) do
    spec = Jobs.Spec.new(Jobs.Spec.Remote.new(nodes), parameters, nil)
    Jobs.Job.new(detail(name), spec)
  end

  defp local_job(name) do
    spec = Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil)
    Jobs.Job.new(detail(name), spec)
  end

  defp detail(name), do: Jobs.Detail.new(name, Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil))
end
