defmodule Exdock.Server.ClientIngressTest do
  use ExUnit.Case, async: true

  alias Exdock.Protocol.Messages.Update
  alias Exdock.Server.ClientIngress

  test "rejects queued messages from a handler after its node name is reassigned" do
    alias Exdock.Server.Connection.TCPServer.ClientRegistry
    registry = start_supervised!({ClientRegistry, name: nil})
    old_handler = start_supervised!({Agent, fn -> :old end})
    replacement = start_supervised!({Agent, fn -> :new end}, id: :replacement)
    message = Update.new("job-id", :container_start, :starting) |> Update.set_node("node-a")
    state = %Exdock.Server.State{}

    :ok = ClientRegistry.register("node-a", old_handler, registry)
    assert :ok = ClientIngress.validate_owner("node-a", old_handler, registry)
    :ok = ClientRegistry.unregister("node-a", old_handler, registry)
    :ok = ClientRegistry.register("node-a", replacement, registry)
    assert {:error, :stale_connection} = ClientIngress.validate_owner("node-a", old_handler, registry)
    assert ClientIngress.accept(state, "node-a", old_handler, message, registry) == state
    assert :ok = ClientIngress.validate_owner("node-a", replacement, registry)
    assert {:error, :stale_connection} = ClientIngress.validate_owner("missing", replacement, registry)
    assert {:error, :connection_registry_unavailable} = ClientIngress.validate_owner("node-a", replacement, :missing_registry)
  end

  test "coordinator messages carry the actual sending handler PID" do
    handler = self()
    message = Update.new("job-id", :container_start, :starting) |> Update.set_node("node-a")
    :ok = Exdock.Runtime.Coordinator.client_message("node-a", message, self())
    assert_receive {:"$gen_cast", {:client_message, ^handler, "node-a", ^message}}
  end

  test "validates authenticated node identity before state dispatch" do
    message = Update.new("job-id", :container_start, :starting) |> Update.set_node("node-a")

    assert {:ok, ^message} = ClientIngress.validate(message, "node-a")
    assert {:error, {:node_mismatch, "node-a", "node-b"}} = ClientIngress.validate(message, "node-b")
    assert {:error, :invalid_message_identity} = ClientIngress.validate(:malformed, "node-a")
  end
end
