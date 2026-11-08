defmodule Exdock.Server.Jobs.RemoteDispatchTest do
  use Exdock.Server.JobsCase, async: false

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.{Event, Result, Runtime, ServerState}
  alias Exdock.Server.JobsTest.CommandSink

  test "publishes parent completion after all distinct execution IDs settle" do
    tcp_server = start_supervised!({CommandSink, self()})
    register_tcp_server(tcp_server)
    first = Jobs.Spec.new(Jobs.Spec.Remote.new("node-a"), [], nil)
    last = Jobs.Spec.new(Jobs.Spec.Remote.new("node-b"), [], nil)
    detail = Jobs.Detail.new(:multi_spec_dispatch, [first, last])
    [{_, first_id}, {_, last_id}] = detail.spec_list
    parent_id = detail.id
    Jobs.add(detail, jobs_server())

    assert_receive {:command_sink, "node-a", %Jobs.Job{id: ^first_id}}, 1_000
    assert_receive {:command_sink, "node-b", %Jobs.Job{id: ^last_id}}, 1_000
    Jobs.job_result(Result.new(first_id, "node-a", :ok), jobs_server())
    assert_receive %Event{type: :job_finished, result: %Result{id: ^first_id}}, 1_000
    assert %ServerState{domain: domain} = :sys.get_state(jobs_server())
    assert Jobs.State.get_job_info(domain, parent_id)
    refute_receive %Event{type: :job_finished, result: %Result{id: ^parent_id}}, 0

    Jobs.job_result(Result.new(last_id, "node-b", :ok), jobs_server())
    assert_receive %Event{type: :job_finished, result: %Result{id: ^last_id}}, 1_000
    assert_receive %Event{type: :job_finished, result: %Result{id: ^parent_id, error: nil}}, 1_000
    assert %ServerState{domain: domain} = :sys.get_state(jobs_server())
    assert Jobs.State.get_job_info(domain, parent_id) == nil
    assert domain.running.jobs == %{}
  end

  test "keeps dispatching when the TCP server is not registered" do
    assert Process.whereis(Exdock.Server.Connection.TCPServer) == nil

    jobs_pid = GenServer.whereis(jobs_server())

    :missing_tcp_server
    |> remote_detail("unregistered_node")
    |> Jobs.add(jobs_server())

    assert_receive %Event{type: :job_started, job: %Jobs.Job{id: job_id}}, 1_000

    assert_receive %Event{
                     type: :job_finished,
                     info: %Jobs.Info{name: :missing_tcp_server},
                     result: %Result{
                       id: ^job_id,
                       node: "unregistered_node",
                       error: :nodedown
                     }
                   },
                   1_000

    _state = :sys.get_state(jobs_pid)
    assert GenServer.whereis(jobs_server()) == jobs_pid
  end

  test "finishes a remote job when the TCP server rejects its dispatch" do
    tcp_server = start_supervised!({CommandSink, {self(), {:error, :node_not_connected}}})
    register_tcp_server(tcp_server)

    :missing_client
    |> remote_detail("disconnected-node")
    |> Jobs.add(jobs_server())

    assert_receive %Event{type: :job_started, job: %Jobs.Job{id: job_id}}, 1_000
    assert_receive {:command_sink, "disconnected-node", %Jobs.Job{id: ^job_id}}, 1_000

    assert_receive %Event{
                     type: :job_finished,
                     info: %Jobs.Info{name: :missing_client},
                     result: %Result{
                       id: ^job_id,
                       node: "disconnected-node",
                       error: :nodedown
                     }
                   },
                   1_000

    assert %ServerState{domain: domain} = :sys.get_state(jobs_server())
    assert Jobs.State.get_job_info(domain, job_id) == nil
  end

  test "settles dispatcher feedback effects before the callback returns" do
    assert Process.whereis(Exdock.Server.Connection.TCPServer) == nil

    detail = remote_detail(:synchronous_feedback, "unregistered_node")

    server_state = ServerState.new(Runtime.new())

    assert {:noreply, %ServerState{domain: state}} =
             Jobs.handle_cast({:add_job, detail}, server_state)

    assert Jobs.State.get_job_info(state, detail.id) == nil

    assert_receive %Event{
      type: :job_finished,
      info: %Jobs.Info{name: :synchronous_feedback},
      result: %Result{id: id, error: :nodedown}
    }

    assert id == detail.id
  end

  test "fails remote jobs without crashing when a string-named node disconnects" do
    jobs_pid = GenServer.whereis(jobs_server())
    tcp_server = start_supervised!({CommandSink, self()})
    register_tcp_server(tcp_server)

    :node_refresh
    |> remote_detail("c3")
    |> Jobs.add(jobs_server())

    assert_receive %Event{type: :job_started, job: %Jobs.Job{id: job_id}}, 1_000
    assert_receive {:command_sink, "c3", %Jobs.Job{id: ^job_id}}, 1_000

    send(jobs_pid, {:nodechange, :down, "c3"})

    assert_receive %Event{
                     type: :job_finished,
                     info: %Jobs.Info{name: :node_refresh},
                     result: %Result{id: ^job_id, node: "c3", error: :nodedown}
                   },
                   1_000

    assert %ServerState{domain: state} = :sys.get_state(jobs_pid)
    assert Jobs.State.get_job_info(state, job_id) == nil
    assert GenServer.whereis(jobs_server()) == jobs_pid
  end

  defp register_tcp_server(tcp_server) do
    Process.register(tcp_server, Exdock.Server.Connection.TCPServer)

    on_exit(fn ->
      if Process.whereis(Exdock.Server.Connection.TCPServer) == tcp_server do
        Process.unregister(Exdock.Server.Connection.TCPServer)
      end
    end)
  end

  test "completes a refresh after its logging consumer restarts" do
    alias Exdock.Server.Logging
    alias Exdock.Server.Logging.Context
    alias Exdock.Runtime.Command.Workflow

    tcp_server = start_supervised!({CommandSink, self()})
    register_tcp_server(tcp_server)
    assert :ok = Exdock.Events.subscribe(:operations)
    owner = self()

    logging_opts = [
      name: nil,
      broadcast: owner,
      jobs: jobs_server(),
      context_provider: fn -> Context.new(~U[2026-11-06 12:00:00Z], Ecto.UUID.generate()) end
    ]

    logging = start_supervised!({Logging, logging_opts})
    payload = Jobs.Payload.NodeRefresh.new(%{"node-a" => [], "node-b" => []}, nil, [])
    spec = Jobs.Spec.new(Jobs.Spec.Remote.new(["node-a", "node-b"]), [], payload)
    detail = Jobs.Detail.new(:node_refresh, spec, continuation: Workflow.new(:registry_fetch, []))
    id = detail.id
    Jobs.add(detail, jobs_server())

    assert_receive {:command_sink, "node-a", %Jobs.Job{id: ^id}}
    assert_receive {:command_sink, "node-b", %Jobs.Job{id: ^id}}
    assert Map.has_key?(Logging.snapshot(logging).status.jobs, {:node_refresh, id})

    Jobs.job_update(Jobs.Update.new(id, "node-a", %{ok: [], errored: []}, true), jobs_server())
    assert_receive %Event{type: :job_updated, update: %Jobs.Update{node: "node-a"}}
    _snapshot = Logging.snapshot(logging)
    stop_supervised!(Logging)
    restarted_logging = start_supervised!({Logging, logging_opts})
    assert Logging.snapshot(restarted_logging).status.jobs == %{}

    Jobs.job_update(Jobs.Update.new(id, "node-b", %{ok: [], errored: []}, true), jobs_server())

    assert_receive %Event{type: :job_finished, result: %Result{id: ^id, error: nil}}
    assert_receive {:exdock_event, :operations, _, %{id: ^id, state: :finished}}
    assert %ServerState{domain: domain} = :sys.get_state(jobs_server())
    assert Jobs.State.get_job_info(domain, id) == nil
    assert domain.continuations == Jobs.State.Continuations.new()
  end
end
