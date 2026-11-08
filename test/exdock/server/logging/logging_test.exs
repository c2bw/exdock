defmodule Exdock.Server.LoggingTest do
  use ExUnit.Case, async: true

  alias Exdock.Events
  alias Exdock.Server.Logging
  alias Exdock.Server.Jobs.{Detail, Event, Job, Message, Package, Spec}
  alias Exdock.Server.Jobs.Payload.ImageAction
  alias Exdock.Server.Logging.{AppendEntry, Context, Log, Status}

  @log_time ~U[2026-07-31 10:00:00.000Z]

  setup do
    owner = self()

    logging =
      start_supervised!(
        {Logging,
         name: nil,
         subscribe?: false,
         broadcast: owner,
         jobs: owner,
         notifier: owner,
         context_provider: fn -> Context.new(@log_time, Ecto.UUID.generate()) end}
      )

    %{logging: logging}
  end

  describe "snapshot/1" do
    test "returns the current status directly", %{logging: logging} do
      assert %{status: %Status{}} = Logging.snapshot(logging)
    end

    test "applies structured image pull progress messages to the dashboard row", %{logging: logging} do
      job = image_pull_job("pull-progress-job")

      send(logging, Event.job_started(job))

      send(
        logging,
        Event.job_message(Message.new("pull-progress-job", :image_pull, "node_a", "extract: 8.4MB/12.0MB"))
      )

      assert %{
               {"node_a", "repo/app:latest"} => %{
                 message: "extract: 8.4MB/12.0MB"
               }
             } = Logging.snapshot(logging).status.dash.image_pull
    end
  end

  test "clear_errors emits admission and terminal completion for its operation", %{logging: logging} do
    :ok = Events.subscribe(:operations)
    operation_id = Ecto.UUID.generate()

    assert :ok = Logging.submit_clear_errors(operation_id, logging)
    _state = :sys.get_state(logging)

    assert_receive {:exdock_event, :operations, _revision,
                    %{
                      id: ^operation_id,
                      kind: :clear_errors,
                      state: :accepted
                    }}

    assert_receive {:exdock_event, :operations, _revision,
                    %{
                      id: ^operation_id,
                      kind: :clear_errors,
                      state: :finished,
                      result: %{status: :completed}
                    }}
  end

  test "submitted error clearing is queued after admission", %{logging: logging} do
    state = :sys.get_state(logging)
    operation_id = Ecto.UUID.generate()

    assert {:reply, :ok, ^state} =
             Logging.handle_call({:submit_clear_errors, operation_id}, self(), state)

    assert_receive {:execute_admitted_clear_errors, ^operation_id}
  end

  describe "log snapshot" do
    test "returns the current log list directly", %{logging: logging} do
      assert %{log: log} = Logging.snapshot(logging)
      assert is_list(log)
    end

    test "accepts a named append input with visibility flags", %{logging: logging} do
      input =
        AppendEntry.new(:node_connected, "node-a",
          automated: true,
          hidden: true,
          broadcast: false
        )

      assert :ok = Logging.add_to_log(input, logging)
      assert [%Log{is_automated: true, hidden: true}] = Logging.snapshot(logging).log
    end

    test "routes broadcast effects to the configured runtime target", %{logging: logging} do
      input = AppendEntry.new(:node_connected, "node-a", broadcast: true)

      assert :ok = Logging.add_to_log(input, logging)

      assert_receive {:"$gen_cast", {:broadcast, {:log, [_entry], [revision: 1]}}}
    end

    test "records ordinary job starts in the visible log", %{logging: logging} do
      job = image_pull_job("pull-job")

      send(logging, Event.job_started(job))

      assert [%Log{} = entry] = Logging.snapshot(logging).log
      assert entry.message_id == :image_pull
      assert entry.message_data == {"node_a", "repo/app:latest"}
      assert entry.entry_data == %{job_id: "pull-job", status: :started}
      refute entry.hidden
    end

    test "records an aggregate package row and its individual detail rows", %{logging: logging} do
      detail = image_pull_detail()
      package = Package.new(:image_pull, [detail], {1, ["repo/app:latest"]})
      [packaged_detail] = package.details
      [{spec, _id}] = packaged_detail.spec_list
      packaged_job = packaged_detail |> Job.new(spec) |> Job.set_running()
      send(logging, Event.package_started(package))
      send(logging, Event.job_started(packaged_job))

      assert [%Log{} = detail_entry, %Log{} = package_entry] = Logging.snapshot(logging).log

      assert detail_entry.message_id == :image_pull
      assert detail_entry.message_data == {"node_a", "repo/app:latest"}
      assert detail_entry.entry_data == %{job_id: packaged_detail.id, status: :started}

      assert package_entry.message_id == :image_pull
      assert package_entry.message_data == {:mass, {1, ["repo/app:latest"]}}
      assert package_entry.entry_data == %{job_id: package.id, status: :started}
    end

    test "projects package completion events into terminal log statuses", %{logging: logging} do
      successful_package = Package.new(:image_pull, [image_pull_detail()], {1, ["repo/app:latest"]})
      failed_package = Package.new(:image_pull, [image_pull_detail()], {1, ["repo/other:latest"]})
      send(logging, Event.package_started(successful_package))
      send(logging, Event.package_started(failed_package))
      send(logging, Event.package_finished(successful_package.id, nil))
      send(logging, Event.package_finished(failed_package.id, :pull_failed))

      entries_by_id =
        Logging.snapshot(logging).log
        |> Map.new(&{&1.entry_data.job_id, &1})

      assert entries_by_id[successful_package.id].entry_data.status == :finished
      assert entries_by_id[failed_package.id].entry_data.status == :errored
    end
  end

  describe "Log helper behavior" do
    test "add_entry stores a bounded capped list and handles plain messages without job data" do
      history =
        Enum.reduce(1..301, [], fn idx, acc ->
          Log.add_entry(acc, AppendEntry.new(:sample, idx), "log-#{idx}", @log_time)
        end)

      assert length(history) == 300
      first_entry = List.first(history)
      assert first_entry.message_id == :sample
      assert first_entry.entry_data == nil
    end

    test "update_entry updates matching job entry, preserves unhidden flag when not requested" do
      history =
        Log.add_entry(
          [],
          AppendEntry.new(:start_message, %{phase: :initial}, "job-1", hidden: true),
          "log-1",
          @log_time
        )

      [first_before | _] = history
      history = Log.update_entry(history, "job-1", :finished, @log_time)

      [first_after | _] = history
      assert first_after.entry_data.job_id == "job-1"
      assert first_after.entry_data.status == :finished
      assert first_after.hidden
      assert first_after.hidden == first_before.hidden
      assert first_after.message_data == first_before.message_data
    end

    test "update_entry can unhide and enrich message data in one pass" do
      history =
        Log.add_entry(
          [],
          AppendEntry.new(:status_update, %{count: 1}, "job-2", hidden: true),
          "log-2",
          @log_time
        )

      history =
        Log.update_entry(history, "job-2", :errored, @log_time,
          unhide: true,
          change_message_data: {:count, 2}
        )

      [entry] = history
      assert entry.hidden == false
      assert entry.entry_data.status == :errored
      assert entry.message_data.count == 2
    end

    test "update_entry honors lazy updates by preserving terminal status" do
      history = Log.add_entry([], AppendEntry.new(:status_update, %{}, "job-3"), "log-3", @log_time)
      history = Log.update_entry(history, "job-3", :errored, @log_time, lazy: true)
      history = Log.update_entry(history, "job-3", :finished, @log_time, lazy: true)

      [entry] = history
      assert entry.entry_data.status == :errored
    end

    test "update_entry is idempotent for entries without a matching job id" do
      history = Log.add_entry([], AppendEntry.new(:plain_message, %{}), "log-4", @log_time)

      assert history == Log.update_entry(history, "job-4", :errored, @log_time)
    end

    test "add_entry uses identity and time supplied by its caller" do
      assert %Log{id: nil, start_time: nil} = %Log{}

      [second] = Log.add_entry([], AppendEntry.new(:sample, :second), "log-2", @log_time)
      [first] = Log.add_entry([], AppendEntry.new(:sample, :first), "log-1", @log_time)

      assert first.id == "log-1"
      assert second.id == "log-2"
      assert first.start_time == @log_time
      assert second.start_time == @log_time
    end
  end

  defp image_pull_job(id) do
    detail = image_pull_detail()
    [{spec, _detail_id}] = detail.spec_list

    detail
    |> Map.put(:id, id)
    |> Job.new(spec)
    |> Job.set_running()
  end

  defp image_pull_detail do
    Detail.new(
      :image_pull,
      Spec.new(
        Spec.Remote.new(["node_a"]),
        ["repo/app:latest"],
        ImageAction.pull("node_a", "repo/app:latest")
      )
    )
  end
end
