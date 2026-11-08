defmodule Exdock.Server.Jobs.State.ResultsTest do
  use ExUnit.Case, async: true

  alias Exdock.Runtime.Command.Workflow
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.State
  alias Exdock.Server.Jobs.State.{Continuations, Linked, Nodes, Packages, Queue, Running}

  test "completes terminal indexes and preserves result effect phase ordering" do
    continuation = Workflow.new(:registry_fetch, [:node_refresh])
    primary = detail(:primary, continuation: continuation)
    dependent = detail(:dependent) |> Jobs.Detail.chain_to(primary)
    package = Jobs.Package.new(:bulk_work, [primary], nil)

    {state, _start_effects} =
      State.new()
      |> State.add(package)
      |> State.add(dependent)
      |> State.transition({:run, :instant})

    monitor_ref = make_ref()

    state = %{
      state
      | linked_id: Linked.add(state.linked_id, "duplicate-id", primary.id)
    }

    state = State.track_local_worker(state, monitor_ref, primary.id)
    result = Jobs.Result.new(primary.id, nil, :completed)

    {state, effects} = State.transition(state, {:result, result})

    assert [
             {:job_finished, %Jobs.Info{name: :primary}, ^result},
             {:job_result, %Jobs.Result{id: "duplicate-id", data: :completed}},
             {:job_started, %Jobs.Job{id: dependent_id}},
             {:start_local, dependent_id, _function},
             {:package_result, package_id, nil},
             {:server_command, ^continuation},
             {:demonitor, ^monitor_ref}
           ] = effects

    assert package_id == package.id
    assert dependent_id == dependent.id
    assert Running.get(state.running, primary.id) == nil
    assert %Jobs.Job{} = Running.get(state.running, dependent.id)
    assert Nodes.ids(state.nodes_jobs, "missing") == []
    assert state.linked_id == Linked.new()
    assert state.packages == Packages.new()
    assert state.queued_jobs == Queue.new()
    assert state.continuations == Continuations.new()
    assert state.local_workers == %{}
    assert State.invariant_errors(state) == []
  end

  defp detail(name, opts \\ []) do
    spec = Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil)
    Jobs.Detail.new(name, spec, opts)
  end
end
