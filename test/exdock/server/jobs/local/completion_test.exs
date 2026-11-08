defmodule Exdock.Server.Jobs.Local.CompletionTest do
  use ExUnit.Case, async: true

  alias Exdock.Runtime.Mutation
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Local.Completion

  test "publishes success only after the state change is acknowledged" do
    test_process = self()
    change = Mutation.tags_info!([])
    result = Jobs.Result.new("registry-job", nil, :done)

    commit = fn received_change ->
      send(test_process, {:committed, received_change})
      :ok
    end

    publish_result = fn received_result ->
      assert_received {:committed, ^change}
      send(test_process, {:published, received_result})
    end

    assert :ok = Completion.publish(change, result, commit, publish_result)
    assert_received {:published, ^result}
  end

  test "publishes a failed job result when the state change is rejected" do
    change = Mutation.repository_releases!([])
    result = Jobs.Result.new("release-job", nil, {:done, []})

    commit = fn ^change -> {:error, :persistence_failed} end
    publish_result = fn failed_result -> send(self(), {:published, failed_result}) end

    assert {:error, :persistence_failed} =
             Completion.publish(change, result, commit, publish_result)

    assert_received {:published,
                     %Jobs.Result{
                       id: "release-job",
                       data: {:done, []},
                       error: {:state_change_failed, :persistence_failed}
                     }}
  end

  test "finishes successful fetch outcomes through the shared state-change protocol" do
    test_process = self()
    change = Mutation.tags_info!([])

    on_success = fn [:tag] -> {change, {:done, 1}} end
    commit = fn ^change -> :ok end
    publish_result = fn result -> send(test_process, {:published, result}) end

    assert :ok =
             Completion.finish(
               "registry-job",
               {:ok, [:tag]},
               on_success,
               commit,
               publish_result
             )

    assert_received {:published, %Jobs.Result{id: "registry-job", data: {:done, 1}, error: nil}}
  end

  test "finishes failed fetch outcomes without attempting a state change" do
    test_process = self()
    commit = fn _change -> flunk("failed fetches must not commit state") end
    publish_result = fn result -> send(test_process, {:published, result}) end

    assert {:error, :timeout} =
             Completion.finish(
               "release-job",
               {:error, :timeout},
               fn _value -> flunk("failed fetches must not build a change") end,
               commit,
               publish_result
             )

    assert_received {:published, %Jobs.Result{id: "release-job", data: :done, error: :timeout}}
  end
end
