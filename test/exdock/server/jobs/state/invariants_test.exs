defmodule Exdock.Server.Jobs.State.InvariantsTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.State
  alias Exdock.Server.Jobs.State.Nodes

  test "reports secondary indexes that reference unknown running jobs" do
    state = State.new()
    inconsistent = %{state | nodes_jobs: %Nodes{nodes: %{"node" => MapSet.new(["missing-job"])}}}

    assert State.invariant_errors(inconsistent) == [node_index: ["missing-job"]]
    assert State.invariant_errors(state) == []
  end
end
