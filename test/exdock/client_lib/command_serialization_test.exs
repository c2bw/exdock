defmodule Exdock.ClientLib.CommandSerializationTest do
  use ExUnit.Case, async: false

  alias Exdock.ClientLib.CommandDispatcher
  alias Exdock.AgentRuntime.Wire
  alias Exdock.TestSupport.BlockingCommandExecutor

  setup do
    start_supervised!({Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor})
    dispatcher = start_supervised!({CommandDispatcher, {"node", self(), BlockingCommandExecutor, Wire, nil}})
    %{dispatcher: dispatcher}
  end

  test "conflicting mutations execute FIFO while other containers and reads can run", %{dispatcher: dispatcher} do
    execute(dispatcher, "recreate", "container_recreate", "app")
    assert_receive {:command_started, "recreate", first}
    execute(dispatcher, "stop", "container_stop", "/app")
    execute(dispatcher, "start", "container_start", "app")
    execute(dispatcher, "restart", "container_restart", "worker")
    execute(dispatcher, "logs", "container_logs", "app")
    state = :sys.get_state(dispatcher)
    assert :queue.len(state.pending_mutations["app"]) == 2
    assert map_size(state.command_tasks) == 3
    assert_receive {:command_started, "restart", other}
    assert_receive {:command_started, "logs", logs}
    send(other, :complete)
    send(logs, :complete)
    send(first, :complete)
    assert_receive {:command_started, "stop", stop}
    assert :queue.len(:sys.get_state(dispatcher).pending_mutations["app"]) == 1
    send(stop, :complete)
    assert_receive {:command_started, "start", start}
    send(start, :complete)
    assert_result("start", nil)
    assert :sys.get_state(dispatcher).pending_mutations == %{}
  end

  for outcome <- [:fail, :kill] do
    @outcome outcome
    test "a worker #{@outcome} releases the next mutation", %{dispatcher: dispatcher} do
      execute(dispatcher, "first", "container_restart", "app")
      assert_receive {:command_started, "first", first}
      execute(dispatcher, "next", "container_stop", "app")
      assert :queue.len(:sys.get_state(dispatcher).pending_mutations["app"]) == 1
      if @outcome == :kill, do: Process.exit(first, :kill), else: send(first, :fail)
      assert_receive {:command_started, "next", next}
      send(next, :complete)
      assert_result("next", nil)
      assert :sys.get_state(dispatcher).command_tasks == %{}
    end
  end

  test "a replacement dispatcher waits for an orphan worker's container lock", %{dispatcher: dispatcher} do
    execute(dispatcher, "old", "container_recreate", "app")
    assert_receive {:command_started, "old", old_worker}
    stop_supervised!(CommandDispatcher)
    replacement = start_supervised!({CommandDispatcher, {"node", self(), BlockingCommandExecutor, Wire, nil}})
    execute(replacement, "new", "container_stop", "app")
    state = :sys.get_state(replacement)
    assert map_size(state.command_tasks) == 1
    assert [{^old_worker, _}] = Registry.lookup(Exdock.AgentRegistry, {:container_mutation, "app"})
    refute_receive {:command_started, "new", _}, 0
    ref = Process.monitor(old_worker)
    send(old_worker, :complete)
    assert_receive {:DOWN, ^ref, :process, ^old_worker, :normal}
    assert_receive {:command_started, "new", new_worker}
    send(new_worker, :complete)
    assert_result("new", nil)
  end

  test "upgrade preparation defers busy dispatchers and closes admission when idle", %{dispatcher: dispatcher} do
    execute(dispatcher, "active", "container_restart", "app")
    assert_receive {:command_started, "active", worker}
    assert {:error, :runtime_busy} = CommandDispatcher.prepare_upgrade(dispatcher)
    send(worker, :complete)
    assert_result("active", nil)
    assert :ok = CommandDispatcher.prepare_upgrade(dispatcher)
    execute(dispatcher, "rejected", "container_stop", "app")
    assert_result("rejected", :runtime_upgrading)
    assert :sys.get_state(dispatcher).command_tasks == %{}
  end

  test "a worker registers before admission and cannot execute when admission is denied" do
    command = %{"id" => "denied", "kind" => "container_restart", "args" => ["app"], "test_owner" => self()}
    tasks = Exdock.ClientLib.CommandRunner.start(%{}, command, BlockingCommandExecutor, nil)
    [{ref, %{pid: worker}}] = Map.to_list(tasks)
    assert_receive {:"$gen_call", from, :authorize_command}
    assert [{^worker, nil}] = Registry.lookup(Exdock.AgentRegistry, {:command_worker, worker})
    GenServer.reply(from, {:error, :runtime_upgrading})
    assert_receive {^ref, {nil, :runtime_upgrading}}
    Process.demonitor(ref, [:flush])
    refute_receive {:command_started, "denied", _}, 0
    assert Registry.lookup(Exdock.AgentRegistry, {:command_worker, worker}) == []
  end

  test "queued and running commands report activity until completion", %{dispatcher: dispatcher} do
    execute(dispatcher, "active", "container_restart", "app")
    assert_receive {:command_started, "active", worker}
    execute(dispatcher, "queued", "container_stop", "app")
    assert_activity("active", "running")
    assert_activity("queued", "queued")
    ref = :sys.get_state(dispatcher).activity_timer
    send(dispatcher, {:timeout, ref, :command_activity})
    assert_activity("active", "running")
    assert_activity("queued", "queued")
    assert :sys.get_state(dispatcher).activity_timer != ref
    send(worker, :complete)
    assert_receive {:command_started, "queued", next}
    send(next, :complete)
    assert_result("queued", nil)
    assert :sys.get_state(dispatcher).activity_timer == nil
    state = :sys.get_state(dispatcher)
    send(dispatcher, {:timeout, ref, :command_activity})
    assert :sys.get_state(dispatcher) == state
  end

  defp execute(dispatcher, id, kind, target) do
    args = if kind == "container_recreate", do: [target, false], else: [target]
    CommandDispatcher.execute(%{"id" => id, "kind" => kind, "args" => args, "test_owner" => self()}, dispatcher)
  end

  defp assert_result(id, error) do
    assert_receive {:"$gen_cast", {:client_message, {:result, %{"id" => ^id, "error" => ^error}}}}, 1_000
  end

  defp assert_activity(id, status) do
    assert_receive {:"$gen_cast", {:client_message, {:progress, %{"id" => ^id, "data" => ^status}}}}, 1_000
  end
end
