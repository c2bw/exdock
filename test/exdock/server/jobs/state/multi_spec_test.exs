defmodule Exdock.Server.Jobs.State.MultiSpecTest do
  use ExUnit.Case, async: true

  alias Exdock.Runtime.Command.Workflow
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.State
  alias Exdock.Server.Jobs.State.{Continuations, Executions, Nodes, Packages, Running}

  test "dispatches each spec under its generated execution ID and waits for all results" do
    continuation = Workflow.new(:registry_fetch, [])
    detail = Jobs.Detail.new(:container_start, [remote("node-a"), remote("node-b")], continuation: continuation)
    [{_, first}, {_, last}] = detail.spec_list
    dependent = Jobs.Detail.new(:registry_fetch, local()) |> Jobs.Detail.chain_to(detail)
    package = Jobs.Package.new(:bulk_work, [detail], nil)
    {state, effects} = State.new() |> State.add(package) |> State.add(dependent) |> State.transition({:run, :instant})

    assert {:start_remote, "node-a", Running.get(state.running, first)} in effects
    assert {:start_remote, "node-b", Running.get(state.running, last)} in effects
    assert Enum.any?(effects, &match?({:job_started, %Jobs.Job{id: id}} when id == detail.id, &1))
    assert map_size(state.running.jobs) == 2
    assert %Jobs.Info{name: :container_start} = State.get_job_info(state, detail.id)
    assert Nodes.ids(state.nodes_jobs, "node-a") == [first]
    assert Nodes.ids(state.nodes_jobs, "node-b") == [last]

    {state, effects} = State.transition(state, {:result, Jobs.Result.new(first, "node-a", :ok)})
    refute finished?(effects, detail.id)
    refute Enum.any?(effects, &match?({:server_command, _}, &1))
    assert Running.get(state.running, dependent.id) == nil
    assert map_size(state.packages.packages) == 1
    assert {^state, []} = State.transition(state, {:result, Jobs.Result.new(first, "node-a", :ok)})

    {state, effects} = State.transition(state, {:result, Jobs.Result.new(last, "node-b", :ok)})
    assert finished?(effects, detail.id)
    assert {:server_command, continuation} in effects
    assert {:package_result, package.id, nil} in effects
    assert %Jobs.Job{} = Running.get(state.running, dependent.id)
    assert State.get_job_info(state, detail.id) == nil
    assert state.executions == Executions.new()
    assert state.continuations == Continuations.new()
    assert state.packages == Packages.new()
    assert State.invariant_errors(state) == []
    assert {^state, []} = State.transition(state, {:result, Jobs.Result.new(last, "node-b", :ok)})
  end

  test "retains an early failure until every mixed local and remote execution settles" do
    detail =
      Jobs.Detail.new(:node_refresh, [remote(["node-a", "node-b"]), local()], continuation: Workflow.new(:registry_fetch, []))

    [{_, remote_id}, {_, local_id}] = detail.spec_list
    dependent = Jobs.Detail.new(:registry_fetch, local()) |> Jobs.Detail.chain_to(detail)
    {state, _} = State.new() |> State.add(detail) |> State.add(dependent) |> State.transition({:run, :instant})
    ref = make_ref()
    state = State.track_local_worker(state, ref, local_id)

    {state, []} = State.transition(state, {:result, Jobs.Result.new(remote_id, "node-a", nil, :nodedown)})
    {state, effects} = State.transition(state, {:update, Jobs.Update.new(remote_id, "node-b", %{}, true)})
    refute finished?(effects, detail.id)
    assert Running.get(state.running, local_id)
    {state, effects} = State.transition(state, {:result, Jobs.Result.new(local_id, nil, :ok)})

    assert {:demonitor, ref} in effects
    assert {:workflow_stopped, :nodedown} in effects
    refute Enum.any?(effects, &match?({:server_command, _}, &1))

    assert Enum.any?(effects, fn
             {:job_finished, _, %Jobs.Result{id: id, node: "node-a", error: :nodedown}} -> id == detail.id
             _ -> false
           end)

    assert state.executions == Executions.new()
    assert state.local_workers == %{}
    assert state.running == Running.new()
    assert state.nodes_jobs == Nodes.new()
    assert state.queued_jobs.queue == []
    assert State.invariant_errors(state) == []
  end

  test "linked duplicate executions complete their parent exactly once" do
    spec = remote("node-a")
    detail = Jobs.Detail.new(:container_start, [spec, spec])
    [{_, owner}, {_, duplicate}] = detail.spec_list
    {state, effects} = State.transition(State.new(), {:add, detail})
    assert Enum.count(effects, &match?({:start_remote, _, _}, &1)) == 1
    assert %Jobs.Job{status: :linked} = Running.get(state.running, duplicate)

    {state, effects} = State.transition(state, {:result, Jobs.Result.new(owner, "node-a", :ok)})
    refute finished?(effects, detail.id)
    assert {:job_result, linked_result} = Enum.find(effects, &match?({:job_result, _}, &1))
    {state, effects} = State.transition(state, {:result, linked_result})
    assert finished?(effects, detail.id)
    assert state.executions == Executions.new()
    assert state.running == Running.new()
    assert {^state, []} = State.transition(state, {:result, linked_result})
  end

  defp finished?(effects, id) do
    Enum.any?(effects, fn
      {:job_finished, _, %Jobs.Result{id: ^id}} -> true
      _ -> false
    end)
  end

  defp remote(nodes), do: Jobs.Spec.new(Jobs.Spec.Remote.new(nodes), ["app"], nil)
  defp local, do: Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil)
end
