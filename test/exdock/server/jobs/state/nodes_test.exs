defmodule Exdock.Server.Jobs.State.NodesTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.State.Nodes

  test "add/2 ignores local jobs" do
    state = Nodes.new()

    assert Nodes.add(state, local_job("local-1")) == state
  end

  test "add/2 indexes a remote job under every target node" do
    state =
      Nodes.new()
      |> Nodes.add(remote_job("remote-1", ["node_a", "node_b"]))

    assert state.nodes == %{"node_a" => MapSet.new(["remote-1"]), "node_b" => MapSet.new(["remote-1"])}
    assert Nodes.ids(state, "node_a") == ["remote-1"]
    assert Nodes.ids(state, "node_b") == ["remote-1"]
    assert Nodes.ids(state, "missing") == []
  end

  test "add/2 deduplicates repeated node entries" do
    state =
      Nodes.new()
      |> Nodes.add(remote_job("remote-1", ["node_a", "node_a"]))

    assert state.nodes == %{"node_a" => MapSet.new(["remote-1"])}
    assert Nodes.ids(state, "node_a") == ["remote-1"]
  end

  test "remove/2 removes a job id and drops empty node buckets" do
    state =
      Nodes.new()
      |> Nodes.add(remote_job("remote-1", ["node_a", "node_b"]))
      |> Nodes.add(remote_job("remote-2", ["node_a"]))
      |> Nodes.remove("remote-1")

    assert Nodes.ids(state, "node_a") == ["remote-2"]
    assert Nodes.ids(state, "node_b") == []
  end

  defp local_job(id) do
    %Jobs.Job{id: id, type: %Jobs.Job.Local{function: fn _ -> :ok end}}
  end

  defp remote_job(id, nodes) do
    %Jobs.Job{id: id, type: %Jobs.Job.Remote{nodes: nodes}}
  end
end
