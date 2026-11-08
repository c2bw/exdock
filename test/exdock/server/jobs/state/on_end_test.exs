defmodule Exdock.Server.Jobs.State.ContinuationsTest do
  use ExUnit.Case, async: true

  alias Exdock.Runtime.Command.Workflow
  alias Exdock.Server.Jobs.State.Continuations

  test "add ignores nil continuations" do
    assert Continuations.add(Continuations.new(), "job-id", nil) == Continuations.new()
  end

  test "failed completion removes a continuation without dispatching it" do
    {state, effects} =
      Continuations.new()
      |> Continuations.add("job-id", Workflow.new(:registry_fetch, []))
      |> Continuations.complete("job-id", :failed)

    assert state == Continuations.new()
    assert effects == [{:workflow_stopped, :failed}]
  end

  test "complete is a no-op for missing continuations" do
    assert Continuations.complete(Continuations.new(), "missing", nil) == {Continuations.new(), []}
  end

  test "successful completion returns the next workflow command as an effect" do
    {state, effects} =
      Continuations.new()
      |> Continuations.add("job-id", Workflow.new(:registry_fetch, [:node_refresh]))
      |> Continuations.complete("job-id", nil)

    assert state == Continuations.new()

    assert effects == [
             {:server_command, Workflow.new(:registry_fetch, [:node_refresh])}
           ]
  end
end
