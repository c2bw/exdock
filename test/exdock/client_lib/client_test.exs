defmodule Exdock.ClientLibTest do
  use ExUnit.Case, async: false

  alias Exdock.ClientLib
  alias Exdock.ClientLib.{Async, AsyncBatchScheduler, CommandDispatcher}
  alias Exdock.AgentRuntime.{Executor, Wire}
  alias Exdock.ClientLib.Jobs.Context
  alias Exdock.Docker.Error
  alias Exdock.Protocol.RuntimeBundle
  alias Exdock.Server.Connection.RuntimeBundleProvider
  alias Exdock.TestSupport.ExplicitContextEngine

  test "downloadable runtime bundle is restricted to AgentRuntime modules" do
    required_modules = RuntimeBundleProvider.required_modules()

    assert length(required_modules) == 4

    assert Enum.all?(required_modules, fn module ->
             name = Atom.to_string(module)
             name == "Elixir.Exdock.AgentRuntime" or String.starts_with?(name, "Elixir.Exdock.AgentRuntime.")
           end)
  end

  test "downloadable runtime bundle contains valid bytecode for every required module" do
    required_modules = RuntimeBundleProvider.required_modules()

    assert {:ok, bundle} = RuntimeBundleProvider.build()
    assert bundle["version"] == RuntimeBundleProvider.version()
    assert Enum.map(bundle["modules"], &elem(&1, 0)) == required_modules

    assert Enum.all?(bundle["modules"], fn {_module, binary, filename} ->
             byte_size(binary) > 0 and (is_binary(filename) or is_list(filename))
           end)

    assert :ok = RuntimeBundle.validate(bundle, &(&1 in required_modules))
  end

  test "unsupported protocol commands return an error and keep the runtime alive" do
    start_supervised!({Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor})
    client_pid = start_supervised!({ClientLib, {"node_a", self(), Executor, Wire}})

    assert Enum.sort(Supervisor.which_children(client_pid) |> Enum.map(&elem(&1, 0))) ==
             Enum.sort([AsyncBatchScheduler, CommandDispatcher])

    assert :sys.get_state(CommandDispatcher).owner == self()

    ClientLib.execute_command(%{"id" => "job-1", "kind" => "container_start", "args" => []})

    assert_receive {:"$gen_cast", {:client_message, {:result, result}}}
    assert result["id"] == "job-1"
    assert result["node"] == "node_a"
    assert result["data"] == nil
    assert result["error"] == {:invalid_command_arguments, "container_start"}
    assert :sys.get_state(CommandDispatcher).command_tasks == %{}
  end

  test "commands receive their Docker context through the explicit execution envelope" do
    start_supervised!({Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor})

    start_supervised!({ClientLib, {"node_a", self(), Executor, Wire, Context.new(ExplicitContextEngine)}})

    ClientLib.execute_command(%{
      "id" => "job-context",
      "kind" => "container_start",
      "args" => ["container-id"]
    })

    assert_receive {:"$gen_cast", {:client_message, {:result, result}}}
    assert result["error"] == :explicit_context
    assert result["data"] == "container-id"
  end

  test "refresh errors cross the protocol boundary without restarting the dispatcher" do
    start_supervised!({Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor})
    start_supervised!({ClientLib, {"node_a", self(), Executor, Wire, Context.new(Exdock.TestSupport.RefreshFailureEngine)}})
    dispatcher = GenServer.whereis(CommandDispatcher)

    for {resources, expected_error} <- [{true, :econnrefused}, {false, :timeout}] do
      ClientLib.execute_command(%{
        "id" => "refresh-failed",
        "kind" => "node_refresh",
        "args" => [%{"retrieve_resources" => resources}]
      })

      assert_receive {:"$gen_cast", {:client_message, {:result, result}}}, 1_000
      assert result["error"] == expected_error
      frame = Exdock.Protocol.Contract.encode_term_frame(:result, result)

      assert {:client_message, %Exdock.Server.Connection.WireMessage{error: ^expected_error}} =
               Exdock.Server.Connection.Protocol.decode_message(frame, :authenticated)

      assert GenServer.whereis(CommandDispatcher) == dispatcher
    end

    ClientLib.execute_command(%{"id" => "after-failure", "kind" => "container_start", "args" => ["app"]})
    assert_receive {:"$gen_cast", {:client_message, {:result, result}}}, 1_000
    assert result["id"] == "after-failure"
    assert result["error"] == nil
  end

  test "a killed refresh worker still emits a decodable terminal error" do
    ref = make_ref()

    state = %CommandDispatcher{
      node: "node_a",
      owner: self(),
      wire: Wire,
      command_tasks: %{ref => %{id: "refresh-killed", kind: "node_refresh", pid: self()}}
    }

    assert {:noreply, updated} = CommandDispatcher.handle_info({:DOWN, ref, :process, self(), :killed}, state)
    assert updated.command_tasks == %{}
    assert_receive {:"$gen_cast", {:client_message, {:result, result}}}
    frame = Exdock.Protocol.Contract.encode_term_frame(:result, result)

    assert {:client_message, %Exdock.Server.Connection.WireMessage{error: {:command_worker_exit, ":killed"}}} =
             Exdock.Server.Connection.Protocol.decode_message(frame, :authenticated)
  end

  test "a killed command worker publishes a terminal error result" do
    ref = make_ref()

    state = %CommandDispatcher{
      node: "node_a",
      owner: self(),
      wire: Wire,
      command_tasks: %{
        ref => %{id: "job-killed", kind: "container_start", pid: self()}
      }
    }

    assert {:noreply, updated_state} =
             CommandDispatcher.handle_info({:DOWN, ref, :process, self(), :killed}, state)

    assert updated_state.command_tasks == %{}

    assert_receive {:"$gen_cast", {:client_message, {:result, result}}}
    assert result["id"] == "job-killed"
    assert result["node"] == "node_a"
    assert result["data"] == nil
    assert result["error"] == {:command_worker_exit, ":killed"}
  end

  test "structured Docker errors become messages only at the protocol boundary" do
    ref = make_ref()
    cause = %Tesla.Env{status: 503}

    state = %CommandDispatcher{
      node: "node_a",
      owner: self(),
      wire: Wire,
      command_tasks: %{
        ref => %{id: "job-failed", kind: "container_start", pid: self()}
      }
    }

    error = Error.new(:container_start, cause)

    assert {:noreply, _state} =
             CommandDispatcher.handle_info({ref, {"container-id", error}}, state)

    assert_receive {:"$gen_cast", {:client_message, {:result, result}}}
    assert result["error"] == "HTTP Error: 503"
    assert error.cause == cause
    assert error.status == 503
    assert error.retryable?
  end

  test "async batches schedule ticks on the owning process without sleeping workers" do
    batch = Async.Batch.new(:sample, "batch-1", 1, 100, fn -> :ok end)

    state = %AsyncBatchScheduler{
      node: "node-a",
      owner: self(),
      async_jobs: Async.new(),
      wire: Wire
    }

    assert {:noreply, scheduled_state} = AsyncBatchScheduler.handle_cast({:add, batch}, state)
    scheduled_batch = Async.get(scheduled_state.async_jobs, :sample, "batch-1")
    assert is_reference(scheduled_batch.generation)
    assert %{scheduled_batch | generation: nil} == batch
    assert_receive {:run_async_batch, ^scheduled_batch}
  end
end
