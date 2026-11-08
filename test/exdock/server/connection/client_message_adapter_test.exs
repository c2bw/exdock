defmodule Exdock.Server.Connection.ClientMessageAdapterTest do
  use ExUnit.Case, async: true

  alias Exdock.Protocol.Messages.{AsyncResult, JobResult, Update}
  alias Exdock.Server.Connection.{ClientMessageAdapter, WireMessage}
  alias Exdock.Server.Jobs.{Job, Result}

  test "converts result DTOs to correlated internal job messages" do
    wire = WireMessage.result("job-id", "container_start", "node-a", "container-id", nil)
    job = %Job{id: "job-id", name: :container_start, parameters: ["container-id"]}

    assert {:ok,
            %JobResult{
              job: ^job,
              result: %Result{id: "job-id", node: "node-a", data: "container-id", error: nil}
            }} = ClientMessageAdapter.to_job_result(wire, job)
  end

  test "converts progress and resource DTOs" do
    assert {:ok, %Update{id: "job-id", name: :container_restart, node: "node-a", data: "starting"}} =
             "job-id"
             |> WireMessage.progress("container_restart", "node-a", "starting")
             |> ClientMessageAdapter.to_internal()

    assert {:ok, %AsyncResult{node: "node-a", name: :container_resources, id: "container-id", result: %{read: 1}}} =
             "node-a"
             |> WireMessage.resource_sample("container-id", %{read: 1})
             |> ClientMessageAdapter.to_internal()
  end

  test "returns a tagged error for unsupported commands" do
    message = %WireMessage{type: :progress, id: "job-id", kind: "unknown", node: "node-a"}
    assert {:error, {:unknown_command, "unknown"}} = ClientMessageAdapter.to_internal(message)
  end
end
