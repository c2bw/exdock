defmodule Exdock.Server.State.ClientMessagesTest do
  use Exdock.Server.State.ClientMessagesCase, async: false

  alias Exdock.AgentRuntime.Wire
  alias Exdock.Protocol.Messages
  alias Exdock.Server.Jobs
  alias Exdock.Server.State.ClientMessages
  alias Exdock.Server.State.Storage.Containers

  test "reduces client updates without performing effects" do
    state = base_state()
    update = %Messages.Update{id: "update-id", name: :container_start, node: "node", data: "still_working"}

    assert {^state,
            [
              {:job_info,
               %Jobs.Message{
                 id: "update-id",
                 name: :container_start,
                 node: "node",
                 message: "still_working"
               }}
            ]} = ClientMessages.reduce(state, update, ~U[2026-07-31 10:00:00Z])

    refute_receive {:captured, _message}
  end

  test "forwards update messages as job info messages" do
    state = base_state()
    update = %Messages.Update{id: "update-id", name: :container_start, node: "node", data: "still_working"}
    _updated_state = commit_client_message(state, update)

    assert_receive {:captured,
                    {:job_info_message,
                     %Jobs.Message{
                       id: "update-id",
                       name: :container_start,
                       node: "node",
                       message: "still_working"
                     }}}
  end

  test "ignores unsupported authenticated messages" do
    state = base_state()
    assert commit_client_message(state, :malformed_authenticated_payload) == state
  end

  test "replaces container resources from async container_resources result" do
    state = state_with_container()
    resources = Wire.encode_result("container_resources", stats_response())

    async = %Messages.AsyncResult{
      node: "node",
      name: :container_resources,
      id: "container-id",
      result: resources
    }

    updated = commit_client_message(state, async)

    assert [%{extended: %{resources: %{records: [%{used_memory: 1024, cpu_usage: 20.0}]}}}] =
             Containers.list_node(updated.cluster.storage, "node")
  end

  test "ignores legacy resource tuples outside the protocol contract" do
    state = state_with_container()

    async = %Messages.AsyncResult{
      node: "node",
      name: :container_resources,
      id: "container-id",
      result: {"container-id", stats_response()}
    }

    updated = commit_client_message(state, async)

    assert [%{extended: %{resources: %{records: []}}}] =
             Containers.list_node(updated.cluster.storage, "node")
  end
end
