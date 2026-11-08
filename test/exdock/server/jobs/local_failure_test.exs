defmodule Exdock.Server.Jobs.LocalFailureTest do
  use Exdock.Server.JobsCase, async: false

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.{Detail, Event, Result, ServerState, Spec}

  test "turns a crashing local job into a failed result without restarting the dispatcher" do
    jobs_pid = GenServer.whereis(jobs_server())

    detail =
      Detail.new(
        :crashing_local_job,
        Spec.new(
          Spec.Local.new(fn _id -> raise "local Docker operation failed" end),
          [],
          nil
        )
      )

    ExUnit.CaptureLog.capture_log(fn ->
      Jobs.add(detail, jobs_server())

      assert_receive %Event{type: :job_started, job: %Jobs.Job{id: job_id}}, 1_000

      assert_receive %Event{
                       type: :job_finished,
                       info: %Jobs.Info{name: :crashing_local_job},
                       result: %Result{
                         id: ^job_id,
                         node: nil,
                         data: nil,
                         error: {:local_job_failed, :error, %RuntimeError{message: "local Docker operation failed"}}
                       }
                     },
                     1_000
    end)

    _state = :sys.get_state(jobs_pid)
    assert GenServer.whereis(jobs_server()) == jobs_pid
  end

  test "installs monitoring before a local function can exit immediately" do
    owner = self()
    jobs_pid = GenServer.whereis(jobs_server())

    function = fn id ->
      send(owner, {:worker_monitors, id, Process.info(self(), :monitored_by)})
      Process.exit(self(), :kill)
    end

    detail = Detail.new(:immediate_exit, Spec.new(Spec.Local.new(function), [], nil))
    id = detail.id

    ExUnit.CaptureLog.capture_log(fn ->
      Jobs.add(detail, jobs_server())
      assert_receive {:worker_monitors, ^id, {:monitored_by, monitors}}, 1_000
      assert jobs_pid in monitors
      assert_receive %Event{type: :job_finished, result: %Result{id: ^id, error: {:local_job_failed, :exit, :killed}}}, 1_000
    end)
  end

  test "turns an untrappable local worker exit into a terminal failed result" do
    jobs_pid = GenServer.whereis(jobs_server())
    owner = self()
    assert :ok = Exdock.Events.subscribe(:operations)

    detail =
      Detail.new(
        :killed_local_job,
        Spec.new(
          Spec.Local.new(fn id ->
            send(owner, {:local_worker_started, self(), id})

            receive do
              :kill_local_worker -> Process.exit(self(), :kill)
            end
          end),
          [],
          nil
        )
      )

    ExUnit.CaptureLog.capture_log(fn ->
      Jobs.add(detail, jobs_server())

      assert_receive %Event{type: :job_started, job: %Jobs.Job{id: job_id}}, 1_000
      assert_receive {:local_worker_started, worker_pid, ^job_id}, 1_000

      worker_ref = Process.monitor(worker_pid)
      send(worker_pid, :kill_local_worker)
      assert_receive {:DOWN, ^worker_ref, :process, ^worker_pid, :killed}, 1_000

      assert_receive %Event{
                       type: :job_finished,
                       info: %Jobs.Info{name: :killed_local_job},
                       result: %Result{
                         id: ^job_id,
                         node: nil,
                         data: nil,
                         error: {:local_job_failed, :exit, :killed}
                       }
                     },
                     1_000

      assert_receive {:exdock_event, :operations, _revision,
                      %{
                        id: ^job_id,
                        kind: :killed_local_job,
                        state: :finished,
                        result: %Result{
                          id: ^job_id,
                          error: {:local_job_failed, :exit, :killed}
                        }
                      }},
                     1_000

      assert %ServerState{domain: domain} = :sys.get_state(jobs_pid)
      assert Jobs.State.get_job_info(domain, job_id) == nil
    end)

    assert GenServer.whereis(jobs_server()) == jobs_pid
  end

  test "terminates local workers when the job engine restarts" do
    jobs_supervisor = GenServer.whereis(jobs_supervisor())
    old_jobs_pid = GenServer.whereis(jobs_server())
    detail = run_blocking_local_detail(:restart_bound_local_job)

    assert_receive %Event{type: :job_started, job: %Jobs.Job{id: job_id}}, 1_000
    assert detail.name == :restart_bound_local_job
    assert_receive {:blocking_local_job_started, worker_pid, ^job_id}, 1_000

    worker_ref = Process.monitor(worker_pid)
    jobs_ref = Process.monitor(old_jobs_pid)
    Process.exit(old_jobs_pid, :kill)

    assert_receive {:DOWN, ^jobs_ref, :process, ^old_jobs_pid, :killed}, 1_000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker_pid, _reason}, 1_000

    _supervisor_state = :sys.get_state(jobs_supervisor)
    new_jobs_pid = GenServer.whereis(jobs_server())
    assert is_pid(new_jobs_pid)
    refute new_jobs_pid == old_jobs_pid
    assert %ServerState{domain: domain} = :sys.get_state(new_jobs_pid)
    assert Jobs.State.get_job_info(domain, job_id) == nil
  end
end
