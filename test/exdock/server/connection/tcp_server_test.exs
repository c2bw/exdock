defmodule Exdock.Server.Connection.TCPServerTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Connection.TCPServer
  alias Exdock.Server.Connection.TCPServer.ClientRegistry
  alias Exdock.Server.Jobs.Job

  setup do
    registry = start_supervised!({ClientRegistry, name: nil})
    %{registry: registry, state: %TCPServer{registry: registry}}
  end

  test "forwards validated commands only to connected clients", %{registry: registry, state: state} do
    job = %Job{id: "job-id", name: :container_start, parameters: ["container"]}
    caller = self()
    handler = spawn(fn -> command_handler(caller) end)

    assert :ok = ClientRegistry.register("node-a", handler, registry)

    assert {:reply, :ok, ^state} =
             TCPServer.handle_call({:send_command, "node-a", job}, self(), state)

    assert_receive {:command_sent, ^job}

    assert {:reply, {:error, :node_not_connected}, ^state} =
             TCPServer.handle_call({:send_command, "node-b", job}, self(), state)
  end

  test "unregisters a client whose handler rejects a command send", %{
    registry: registry,
    state: state
  } do
    caller = self()
    handler = spawn(fn -> command_handler(caller, {:error, :closed}) end)
    job = %Job{id: "job-id", name: :container_start, parameters: ["container"]}

    assert :ok = ClientRegistry.register("node-a", handler, registry)

    assert {:reply, {:error, {:command_send_failed, :closed}}, ^state} =
             TCPServer.handle_call({:send_command, "node-a", job}, self(), state)

    assert ClientRegistry.fetch("node-a", registry) == :error
  end

  test "terminates a timed-out handler before its name can be reused", %{registry: registry, state: state} do
    handler = start_supervised!({Exdock.TestSupport.ConnectionCommandHandler, :timeout})
    monitor = Process.monitor(handler)
    :ok = ClientRegistry.register("node-a", handler, registry)
    job = %Job{id: "timed-out-job", name: :container_start, parameters: ["app"]}

    assert {:reply, {:error, {:command_send_failed, {:handler_exit, {:timeout, _}}}}, ^state} =
             TCPServer.handle_call({:send_command, "node-a", job}, self(), state)

    assert_receive {:DOWN, ^monitor, :process, ^handler, :killed}, 1_000
    assert ClientRegistry.fetch("node-a", registry) == :error
    replacement = start_supervised!({Agent, fn -> :replacement end})
    assert :ok = ClientRegistry.register("node-a", replacement, registry)
  end

  test "failed dispatch cleanup cannot terminate a replacement connection", %{registry: registry, state: state} do
    replacement = start_supervised!({Agent, fn -> :replacement end})
    handler = start_supervised!({Exdock.TestSupport.ConnectionCommandHandler, {:replace, registry, replacement}})
    monitor = Process.monitor(handler)
    :ok = ClientRegistry.register("node-a", handler, registry)
    job = %Job{id: "replaced-job", name: :container_start, parameters: ["app"]}

    assert {:reply, {:error, {:command_send_failed, :closed}}, ^state} =
             TCPServer.handle_call({:send_command, "node-a", job}, self(), state)

    assert_receive {:DOWN, ^monitor, :process, ^handler, :killed}, 1_000
    assert ClientRegistry.fetch("node-a", registry) == {:ok, replacement}
    assert Agent.get(replacement, & &1) == :replacement
  end

  test "accepts ready acknowledgements only from the registered handler", %{
    registry: registry,
    state: state
  } do
    metadata = %{"platform" => "linux/amd64"}
    assert :ok = ClientRegistry.register("node-a", self(), registry)

    assert {:noreply, ^state} =
             TCPServer.handle_info({:client_ready, self(), "node-a", metadata}, state)

    unregistered = spawn(fn -> :ok end)

    assert {:noreply, ^state} =
             TCPServer.handle_info(
               {:client_ready, unregistered, "node-a", metadata},
               state
             )
  end

  test "reads connected clients from the registry", %{registry: registry, state: state} do
    assert :ok = ClientRegistry.register("node-a", self(), registry)

    assert {:reply, %{"node-a" => handler}, ^state} =
             TCPServer.handle_call(:connected_clients, self(), state)

    assert handler == self()
  end

  defp command_handler(owner, reply \\ :ok) do
    receive do
      {:"$gen_call", from, {:send_command, job}} ->
        send(owner, {:command_sent, job})
        GenServer.reply(from, reply)
    end
  end
end
