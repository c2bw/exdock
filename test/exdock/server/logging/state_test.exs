defmodule Exdock.Server.Logging.StateTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.{Detail, Event, Job, Spec}
  alias Exdock.Server.Jobs.Payload.ImageAction
  alias Exdock.Server.Logging.{AppendEntry, Context, Log, State}

  @now ~U[2026-07-31 10:00:00.000Z]
  @context Context.new(@now, "log-id")

  test "reduces explicit log commands without running broadcast effects" do
    {state, effects} =
      State.transition(
        State.new(),
        AppendEntry.new(:node_connected, "node-a"),
        @context
      )

    assert state.revision == 1
    assert [%Log{message_id: :node_connected, message_data: "node-a"}] = state.logs
    assert [{:broadcast, :log, state.logs, 1}] == effects
  end

  test "preserves named append options without positional booleans" do
    input =
      AppendEntry.new(:node_connected, "node-a",
        automated: true,
        hidden: true,
        broadcast: false
      )

    {state, effects} = State.transition(State.new(), input, @context)

    assert [%Log{is_automated: true, hidden: true}] = state.logs
    assert effects == []
  end

  test "reduces job lifecycle events into ordered log and status effects" do
    detail =
      Detail.new(
        :image_pull,
        Spec.new(
          Spec.Remote.new(["node-a"]),
          ["repo/app:latest"],
          ImageAction.pull("node-a", "repo/app:latest")
        )
      )

    [{spec, _detail_id}] = detail.spec_list
    job = detail |> Map.put(:id, "job-1") |> Job.new(spec) |> Job.set_running()

    {state, effects} = State.transition(State.new(), Event.job_started(job), @context)

    assert state.revision == 2

    assert [%Log{id: "log-id", start_time: @now, entry_data: %{job_id: "job-1", status: :started}}] =
             state.logs

    assert [
             {:broadcast, :log, _logs, 1},
             {:broadcast, :status, _status, 2}
           ] = effects
  end
end
