defmodule Exdock.Server.Jobs.PackageLifecycleTest do
  use Exdock.Server.JobsCase, async: false

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.{Event, Package, Result}

  test "publishes package completion when the logging process is absent" do
    assert Process.whereis(Exdock.Server.Logging) == nil
    assert :ok = Exdock.Events.subscribe(:operations)

    detail = blocking_local_detail(:package_without_logging)
    package = Package.new(:image_pull, [detail], {1, ["repo/app:latest"]})
    Jobs.add(package, jobs_server())

    assert_receive %Event{type: :package_started, package: ^package}, 1_000
    assert_receive %Event{type: :job_started, job: %Jobs.Job{id: job_id}}, 1_000
    assert_receive {:blocking_local_job_started, task_pid, ^job_id}, 1_000

    Jobs.job_result(Result.new(job_id, nil, :done, nil), jobs_server())

    assert_receive %Event{
                     type: :package_finished,
                     package_id: package_id,
                     error: nil
                   },
                   1_000

    assert package_id == package.id

    assert_receive {:exdock_event, :operations, _revision,
                    %{
                      id: ^package_id,
                      kind: :package,
                      state: :finished,
                      result: nil
                    }},
                   1_000

    send(task_pid, {:finish_local_job, job_id})
  end

  test "announces package logging before starting its individual details" do
    detail = blocking_local_detail(:packaged_pull)
    package = Package.new(:image_pull, [detail], {1, ["repo/app:latest"]})

    Jobs.add(package, jobs_server())

    assert_receive %Event{type: :package_started, package: ^package}, 1_000
    assert_receive %Event{type: :job_started, job: %Jobs.Job{id: job_id}}, 1_000
    assert_receive {:blocking_local_job_started, task_pid, ^job_id}, 1_000
    send(task_pid, {:finish_local_job, job_id})
  end
end
