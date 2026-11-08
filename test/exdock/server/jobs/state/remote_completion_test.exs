defmodule Exdock.Server.Jobs.State.RemoteCompletionTest do
  use ExUnit.Case, async: true

  alias Exdock.Runtime.Command.Workflow
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.State
  alias Exdock.Server.Jobs.State.{Continuations, Nodes, Running}

  test "retains disconnect tracking until every target has completed" do
    {state, detail, _continuation} = start_refresh()

    {state, effects} = State.transition(state, {:result, Jobs.Result.new(detail.id, "node-a", nil, :nodedown)})

    assert effects == []
    assert Nodes.ids(state.nodes_jobs, "node-a") == []
    assert Nodes.ids(state.nodes_jobs, "node-b") == [detail.id]
    assert %Jobs.Job{type: %Jobs.Job.Remote{nodes: ["node-b"]}} = Running.get(state.running, detail.id)

    {state, effects} = State.transition(state, {:result, Jobs.Result.new(detail.id, "node-b", nil, :nodedown)})

    assert {:workflow_stopped, :nodedown} in effects
    assert Running.get(state.running, detail.id) == nil
    assert Nodes.ids(state.nodes_jobs, "node-b") == []
    assert state.continuations == Continuations.new()
    assert State.invariant_errors(state) == []
  end

  test "refresh updates complete workflows without a logging consumer" do
    {state, detail, continuation} = start_refresh()
    first = Jobs.Update.new(detail.id, "node-a", %{}, true)
    last = Jobs.Update.new(detail.id, "node-b", %{}, true)

    {state, []} = State.transition(state, {:update, first})
    assert Nodes.ids(state.nodes_jobs, "node-b") == [detail.id]
    assert {^state, []} = State.transition(state, {:update, first})

    {state, effects} = State.transition(state, {:update, last})

    assert {:server_command, continuation} in effects
    assert Running.get(state.running, detail.id) == nil
    assert state.continuations == Continuations.new()
    assert {^state, []} = State.transition(state, {:update, last})
  end

  test "a successful last response cannot hide an earlier refresh failure" do
    {state, detail, _continuation} = start_refresh()
    package = Jobs.Package.new(:refresh, [detail], nil)
    state = %{state | packages: Jobs.State.Packages.add(state.packages, package)}

    {state, []} = State.transition(state, {:update, Jobs.Update.new(detail.id, "node-a", %{}, true, :failed)})
    {state, effects} = State.transition(state, {:update, Jobs.Update.new(detail.id, "node-b", %{}, true)})

    assert {:workflow_stopped, :error} in effects
    assert {:package_result, package.id, :error} in effects
    assert state.remote_errors == %{}
  end

  test "disconnect failures survive a successful last response" do
    {state, detail, _continuation} = start_refresh()
    {state, []} = State.transition(state, {:result, Jobs.Result.new(detail.id, "node-a", nil, :nodedown)})
    {state, effects} = State.transition(state, {:update, Jobs.Update.new(detail.id, "node-b", %{}, true)})

    assert {:workflow_stopped, :nodedown} in effects
    assert state.remote_errors == %{}
    assert Nodes.ids(state.nodes_jobs, "node-b") == []

    assert Enum.any?(effects, fn
             {:job_finished, _, %Jobs.Result{node: "node-a", error: :nodedown}} -> true
             _ -> false
           end)
  end

  test "linked remote jobs settle after their owner completes every target" do
    spec = Jobs.Spec.new(Jobs.Spec.Remote.new(["node-a", "node-b"]), ["app"], nil)
    primary = Jobs.Detail.new(:container_start, spec)
    duplicate = Jobs.Detail.new(:container_start, spec)
    {state, _effects} = State.transition(State.new(), {:add, primary})
    {state, _effects} = State.transition(state, {:add, duplicate})
    assert %Jobs.Job{status: :linked} = Running.get(state.running, duplicate.id)
    assert Nodes.ids(state.nodes_jobs, "node-a") == [primary.id]
    assert Nodes.ids(state.nodes_jobs, "node-b") == [primary.id]

    {state, []} = State.transition(state, {:result, Jobs.Result.new(primary.id, "node-a", nil)})
    {state, effects} = State.transition(state, {:result, Jobs.Result.new(primary.id, "node-b", nil)})
    assert {:job_result, linked_result} = Enum.find(effects, &match?({:job_result, _}, &1))
    assert linked_result.id == duplicate.id

    {state, _effects} = State.transition(state, {:result, linked_result})
    assert state.running == Running.new()
    assert state.nodes_jobs == Nodes.new()
    assert state.remote_errors == %{}
  end

  test "node-removing progress cannot finish a local job" do
    spec = Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil)
    detail = Jobs.Detail.new(:registry_fetch, spec)
    {state, _effects} = State.transition(State.new(), {:add, detail})

    assert {^state, []} = State.transition(state, {:update, Jobs.Update.new(detail.id, nil, %{}, true)})
  end

  defp start_refresh do
    continuation = Workflow.new(:registry_fetch, [])
    spec = Jobs.Spec.new(Jobs.Spec.Remote.new(["node-a", "node-b"]), [], nil)
    detail = Jobs.Detail.new(:node_refresh, spec, continuation: continuation)
    {state, _effects} = State.transition(State.new(), {:add, detail})
    {state, detail, continuation}
  end
end
