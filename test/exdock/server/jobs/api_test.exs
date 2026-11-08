defmodule Exdock.Server.Jobs.ApiTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.{Detail, Event, Message, Result, ServerState, Spec, Update}

  test "job events can target an isolated mailbox" do
    result = Result.new("job-id", "node-a", :done, nil)
    update = Update.new("job-id", "node-a", %{step: :running}, false)
    message = Message.new("job-id", :container_start, "node-a", "working")

    assert :ok = Jobs.job_result(result, self())
    assert :ok = Jobs.job_update(update, self())
    assert :ok = Jobs.info_message(message, self())

    assert_receive {:"$gen_cast", {:job_result, ^result}}
    assert_receive {:"$gen_cast", {:job_update, ^update}}
    assert_receive {:"$gen_cast", {:job_info_message, ^message}}
  end

  test "an isolated dispatcher keeps local execution and publication on its runtime targets" do
    pubsub = Exdock.Server.Jobs.ApiTest.PubSub
    start_supervised!({Phoenix.PubSub, name: pubsub})
    task_supervisor = start_supervised!({Task.Supervisor, name: nil})

    jobs =
      start_supervised!(%{
        id: :isolated_jobs,
        start:
          {Jobs, :start_link,
           [
             [
               name: nil,
               task_supervisor: task_supervisor,
               coordinator: self(),
               connection: self(),
               pubsub: pubsub
             ]
           ]}
      })

    :ok = Jobs.subscribe(pubsub)
    owner = self()

    detail =
      Detail.new(
        :isolated_local,
        Spec.new(
          Spec.Local.new(fn id, runtime ->
            send(owner, {:isolated_runtime, runtime})
            Jobs.job_result(Result.new(id, nil, :done, nil), runtime.jobs)
          end),
          [],
          nil
        )
      )

    Jobs.add(detail, jobs)

    assert_receive %Event{type: :job_started, job: %Jobs.Job{id: job_id}}, 1_000
    assert_receive {:isolated_runtime, %{jobs: ^jobs, task_supervisor: ^task_supervisor}}, 1_000
    assert_receive %Event{type: :job_finished, result: %Result{id: ^job_id, data: :done}}, 1_000
    assert %ServerState{domain: domain} = :sys.get_state(jobs)
    assert Jobs.State.get_job_info(domain, job_id) == nil
  end
end
