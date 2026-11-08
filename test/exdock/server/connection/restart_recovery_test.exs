defmodule Exdock.Server.Connection.RestartRecoveryTest do
  use Exdock.DataCase, async: false
  use Exdock.Server.JobsCase

  alias Exdock.Runtime.Coordinator
  alias Exdock.Server
  alias Exdock.Server.Connection
  alias Connection.TCPServer
  alias TCPServer.{ClientRegistry, HandlerSupervisor}
  alias Exdock.Server.Jobs
  alias Exdock.Server.State.Storage
  alias Exdock.TestSupport.ConnectionCommandHandler

  for failed_child <- [ClientRegistry, TCPServer] do
    @failed_child failed_child
    test "recovers online nodes and pending jobs after #{inspect(failed_child)} crashes" do
      coordinator = start_supervised!({Server, email: "recovery@example.com", plain_password: "test-password-123"})
      :ok = Phoenix.PubSub.subscribe(Exdock.PubSub, "nodechange")
      supervisor = start_supervised!({Connection.Supervisor, {"recovery-auth", available_port()}})
      _ = :sys.get_state(coordinator)

      :sys.replace_state(coordinator, fn state ->
        node = Exdock.Domain.Node.default("node-a")
        storage = Storage.Nodes.set(state.cluster.storage, "node-a", node)
        %{state | cluster: %{state.cluster | storage: storage}}
      end)

      {:ok, handler} = DynamicSupervisor.start_child(HandlerSupervisor, {ConnectionCommandHandler, {:accept, self()}})
      :ok = ClientRegistry.register("node-a", handler)
      detail = remote_detail(:container_start, "node-a")
      Jobs.add(detail, jobs_server())
      job_id = detail.id
      assert_receive {:command_accepted, %Jobs.Job{id: ^job_id}}, 1_000

      failed = Process.whereis(@failed_child)
      monitor = Process.monitor(handler)
      :erlang.trace(supervisor, true, [:procs])
      Process.exit(failed, :kill)
      assert_receive {:trace, ^supervisor, :spawn, replacement, _}, 1_000
      _ = :sys.get_state(replacement)
      :erlang.trace(supervisor, false, [:procs])
      assert_receive {:DOWN, ^monitor, :process, ^handler, :shutdown}, 1_000
      assert_receive {:nodechange, :down, "node-a"}, 1_000

      assert_receive %Jobs.Event{
                       type: :job_finished,
                       result: %Jobs.Result{id: ^job_id, node: "node-a", error: :nodedown}
                     },
                     1_000

      assert Storage.Nodes.list(:sys.get_state(coordinator).cluster.storage) == []
      assert Jobs.State.get_job_info(:sys.get_state(GenServer.whereis(jobs_server())).domain, job_id) == nil

      # Querying the supervisor waits until all replacement children are started.
      _ = Supervisor.which_children(supervisor)
      {:ok, new_handler} = DynamicSupervisor.start_child(HandlerSupervisor, {ConnectionCommandHandler, {:accept, self()}})
      assert :ok = ClientRegistry.register("node-a", new_handler)
      send(TCPServer, {:client_ready, new_handler, "node-a", %{"platform" => "linux/amd64"}})
      assert_receive {:nodechange, :up, "node-a"}, 1_000
      assert Storage.Nodes.get(:sys.get_state(coordinator).cluster.storage, "node-a")
      assert Process.whereis(Coordinator) == coordinator
    end
  end

  defp available_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
