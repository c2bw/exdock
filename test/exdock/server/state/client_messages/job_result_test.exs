defmodule Exdock.Server.State.ClientMessages.JobResultTest do
  use Exdock.Server.State.ClientMessagesCase, async: false

  alias Exdock.Protocol.Messages
  alias Exdock.Runtime.Command
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.{Job, Result}
  alias Exdock.Server.State.Storage.Containers

  test "schedules a node refresh and emits a finished result for successful container jobs" do
    state = state_with_container()
    result = %Result{node: "node", data: "container-id", error: nil}
    message = %Messages.JobResult{job: %Job{id: "start-id", name: :container_start}, result: result}

    _updated = commit_client_message(state, message)

    assert_receive {:captured, {:job_result, %Jobs.Result{id: "start-id", data: "container-id", error: nil}}}

    assert_receive {:captured_info,
                    {:delayed_command, nil, %Command.Cluster{action: :refresh_node, node: "node", condition: :no}, [delay: 50]}}
  end

  test "schedules reconciliation even when a container action reports an error" do
    state = state_with_container()
    result = %Result{node: "node", data: "container-id", error: "no such container"}
    message = %Messages.JobResult{job: %Job{id: "start-id", name: :container_start}, result: result}

    _updated = commit_client_message(state, message)

    assert_receive {:captured,
                    {:job_result,
                     %Jobs.Result{
                       id: "start-id",
                       data: "container-id",
                       error: "no such container"
                     }}}

    assert_receive {:captured_info,
                    {:delayed_command, nil, %Command.Cluster{action: :refresh_node, node: "node", condition: :no}, [delay: 50]}}
  end

  test "failed rollback still reconciles Docker state and preserves the recreation error" do
    state = state_with_container()
    error = "start_replacement: failed; rollback errors: restart_original: failed"

    message = %Messages.JobResult{
      job: %Job{id: "recreate-id", name: :container_recreate},
      result: %Result{node: "node", data: "app", error: error}
    }

    _updated = commit_client_message(state, message)

    assert_receive {:captured, {:job_result, %Jobs.Result{id: "recreate-id", error: ^error}}}

    assert_receive {:captured_info,
                    {:delayed_command, nil, %Command.Cluster{action: :refresh_node, node: "node", condition: :no}, [delay: 50]}}
  end

  test "updates logs when container_logs succeeds" do
    occurred_at = ~U[2026-07-31 12:00:00Z]
    state = state_with_container("logs-id")
    result = %Result{node: "node", data: {"logs-id", ["line-a", "line-b"]}, error: nil}
    message = %Messages.JobResult{job: %Job{id: "logs-id", name: :container_logs}, result: result}

    updated = commit_client_message(state, message, occurred_at)

    assert_receive {:captured, {:job_result, %Jobs.Result{id: "logs-id", data: "logs-id", error: nil}}}

    [container] = Containers.list_node(updated.cluster.storage, "node")
    assert container.extended.logs.lines == ["line-a", "line-b"]
    assert container.extended.logs.time == occurred_at
  end

  test "completes container_logs when the client worker fails without data" do
    state = state_with_container("logs-id")
    result = %Result{node: "node", data: nil, error: {:command_worker_exit, ":killed"}}
    message = %Messages.JobResult{job: %Job{id: "logs-id", name: :container_logs}, result: result}

    assert ^state = commit_client_message(state, message)

    assert_receive {:captured,
                    {:job_result,
                     %Jobs.Result{
                       id: "logs-id",
                       node: "node",
                       data: nil,
                       error: {:command_worker_exit, ":killed"}
                     }}}
  end

  test "returns same behavior for image pull success and schedules refresh" do
    state = state_with_container()
    result = %Result{node: "node", data: "example/app:latest", error: nil}
    message = %Messages.JobResult{job: %Job{id: "pull-id", name: :image_pull}, result: result}

    _updated = commit_client_message(state, message)

    assert_receive {:captured,
                    {:job_result,
                     %Jobs.Result{
                       id: "pull-id",
                       data: "example/app:latest",
                       error: nil
                     }}}

    assert_receive {:captured_info,
                    {:delayed_command, nil, %Command.Cluster{action: :refresh_node, node: "node", condition: :no}, [delay: 50]}}
  end
end
