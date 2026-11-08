defmodule Exdock.ServerTest do
  use Exdock.DataCase, async: false

  alias Exdock.Protocol.Messages.JobResult
  alias Exdock.Events
  alias Exdock.Runtime.Command
  alias Exdock.Runtime.Mutation
  alias Exdock.Server
  alias Exdock.Server.Jobs.{Job, Result}
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage

  setup do
    :ok = Events.subscribe(:operations)
    :ok
  end

  test "malformed nested client results do not crash the server callback" do
    registry = start_supervised!({Exdock.Server.Connection.TCPServer.ClientRegistry, []})
    :ok = Exdock.Server.Connection.TCPServer.ClientRegistry.register("node", self(), registry)
    state = %State{}

    malformed = %JobResult{
      job: %Job{id: "job-id", name: :node_refresh},
      result: %Result{id: "job-id", node: :node, data: :invalid_snapshot, error: nil}
    }

    assert {:noreply, ^state} = Server.handle_cast({:client_message, self(), "node", malformed}, state)
  end

  test "messages cannot claim another authenticated node's identity" do
    registry = start_supervised!({Exdock.Server.Connection.TCPServer.ClientRegistry, []})
    :ok = Exdock.Server.Connection.TCPServer.ClientRegistry.register("authenticated-node", self(), registry)
    state = %State{}

    message = %Exdock.Protocol.Messages.Update{
      node: :other_node,
      id: "job-id",
      name: :container_start,
      data: "starting",
      data_type: :string
    }

    assert {:noreply, ^state} = Server.handle_cast({:client_message, self(), "authenticated-node", message}, state)
  end

  test "the registered connection can still commit resource samples" do
    alias Exdock.Server.State.ClientMessagesFixtures, as: Fixtures
    registry = start_supervised!({Exdock.Server.Connection.TCPServer.ClientRegistry, []})
    :ok = Exdock.Server.Connection.TCPServer.ClientRegistry.register("node", self(), registry)
    state = Fixtures.state_with_container()
    message = Exdock.Protocol.Messages.AsyncResult.new("node", :container_resources, "container-id", Fixtures.stats_response())
    assert {:noreply, updated} = Server.handle_cast({:client_message, self(), "node", message}, state)
    [container] = Storage.Containers.list_node(updated.cluster.storage, "node")
    assert length(container.extended.resources.records) == 1
  end

  test "delayed commands use the same validated execution path" do
    state = %State{}
    command = %Mutation{domain: :settings, action: :user_setting, data: {:unknown, true}}

    assert {:noreply, ^state} =
             Server.handle_info({:delayed_command, nil, command, [delay: 10]}, state)
  end

  test "admitted commands are queued before execution" do
    state = %State{}
    operation_id = Ecto.UUID.generate()
    command = %Mutation{domain: :settings, action: :user_setting, data: {:unknown, true}}
    opts = [operation_kind: :change_user_setting]

    assert {:reply, :ok, ^state} =
             Server.handle_call({:submit_command, operation_id, command, opts}, self(), state)

    assert_receive {:execute_admitted_command, ^operation_id, ^command, ^opts}
  end

  test "admitted automation is queued before execution" do
    state = State.create()
    operation_id = Ecto.UUID.generate()

    assert {:reply, :ok, ^state} =
             Server.handle_call({:submit_periodic_job, operation_id}, self(), state)

    assert_receive {:execute_admitted_periodic_job, ^operation_id}
  end

  test "invalid setting commands leave authoritative state intact" do
    state = %State{}

    assert {:noreply, ^state} =
             Server.handle_cast(
               {:command, nil, %Mutation{domain: :settings, action: :user_setting, data: {:unknown, true}}, []},
               state
             )
  end

  test "state mutations emit terminal operation completion" do
    state = State.create()
    current = Storage.Settings.get(state.settings).container_resources
    operation_id = Ecto.UUID.generate()

    assert {:noreply, %State{} = updated_state} =
             Server.handle_cast(
               {:command, operation_id, Mutation.user_setting!(:container_resources, not current),
                operation_kind: :change_user_setting},
               state
             )

    assert Storage.Settings.get(updated_state.settings).container_resources == not current

    assert_receive {:exdock_event, :operations, _revision,
                    %{
                      id: ^operation_id,
                      kind: :change_user_setting,
                      state: :finished,
                      result: %{status: :completed}
                    }}
  end

  test "commands with no work emit terminal no-op completion" do
    state = State.create()
    operation_id = Ecto.UUID.generate()

    assert {:noreply, ^state} =
             Server.handle_cast(
               {:command, operation_id, Command.Cluster.refresh_node("missing-node", :normal), operation_kind: :refresh_node},
               state
             )

    assert_receive {:exdock_event, :operations, _revision,
                    %{
                      id: ^operation_id,
                      kind: :refresh_node,
                      state: :finished,
                      result: %{status: :noop}
                    }}
  end

  test "manual automation emits terminal completion after rolling the scheduler" do
    state = State.create()
    operation_id = Ecto.UUID.generate()

    assert {:noreply, %State{revision: revision}} =
             Server.handle_cast({:run_periodic_job, operation_id}, state)

    assert revision == state.revision + 1

    assert_receive {:exdock_event, :operations, _revision,
                    %{
                      id: ^operation_id,
                      kind: :run_automation,
                      state: :finished,
                      result: %{status: :completed}
                    }}
  end
end
