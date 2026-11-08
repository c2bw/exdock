defmodule Exdock.Server.JobsTest do
  use Exdock.Server.JobsCase, async: false

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.{Event, Result, Update}

  test "forwards job updates and results to jobs topic with normalized metadata" do
    detail = run_blocking_local_detail(:jobs_refactor_fixture)
    job_id = detail.id
    task_pid = get_started_task_pid()
    update = Update.new(job_id, "node_a", %{step: :checkpoint}, false)
    Jobs.job_update(update, jobs_server())

    assert_receive %Event{
                     type: :job_updated,
                     info: %Jobs.Info{name: :jobs_refactor_fixture, automated: false},
                     update: ^update
                   },
                   1_000

    Jobs.job_result(Result.new(job_id, "node_a", "ok", nil), jobs_server())

    assert_receive %Event{
                     type: :job_finished,
                     info: %Jobs.Info{name: :jobs_refactor_fixture, automated: false},
                     result: %Result{id: ^job_id}
                   },
                   1_000

    send(task_pid, {:finish_local_job, job_id})
  end

  test "ignores update/result messages for unknown jobs in pubsub fanout" do
    unknown_result = Result.new("missing-job", "node_a", "not-found", nil)
    Jobs.job_result(unknown_result, jobs_server())
    refute_receive %Event{type: :job_finished, result: ^unknown_result}, 150

    unknown_update = Update.new("missing-job", "node_a", %{step: :missing}, false, :not_ready)
    Jobs.job_update(unknown_update, jobs_server())
    refute_receive %Event{type: :job_updated, update: ^unknown_update}, 150
  end
end
