defmodule Exdock.Server.Connection.RestartRecoveryTest do
  use Exdock.DataCase, async: false
  use Exdock.Server.JobsCase

  alias Exdock.Runtime.Coordinator
  alias Exdock.Server
  alias Exdock.Server.Connection
  alias Connection.TCPServer
  alias TCPServer.ClientRegistry
  alias Exdock.Server.Jobs
  alias Exdock.Server.State.Storage

  for failed_child <- [ClientRegistry, TCPServer] do
    @failed_child failed_child
    test "recovers online nodes and pending jobs after #{inspect(failed_child)} crashes" do
      coordinator =
        start_supervised!({Server, email: "recovery@example.com", plain_password: "test-password-123"})

      :ok = Phoenix.PubSub.subscribe(Exdock.PubSub, "nodechange")
      supervisor = start_supervised!({Connection.Supervisor, {"recovery-auth", available_port()}})
      _ = :sys.get_state(coordinator)

      :sys.replace_state(coordinator, fn state ->
        node = Exdock.Domain.Node.default("node-a")
        storage = Storage.Nodes.set(state.cluster.storage, "node-a", node)
        %{state | cluster: %{state.cluster | storage: storage}}
      end)

      client = start_agent()
      assert_receive {:nodechange, :up, "node-a"}, 2000
      handler = NodeWire.Client.status(client).connection.owner
      detail = Jobs.Detail.new(:container_start, Jobs.Spec.new(Jobs.Spec.Remote.new("node-a"), ["container-1"], nil))
      Jobs.add(detail, jobs_server())
      job_id = detail.id
      assert_receive {:command_accepted, %{"id" => ^job_id}}, 1_000

      failed = Process.whereis(@failed_child)
      monitor = Process.monitor(handler)
      :erlang.trace(supervisor, true, [:procs])
      Process.exit(failed, :kill)
      assert_receive {:trace, ^supervisor, :spawn, replacement, _}, 1_000
      _ = :sys.get_state(replacement)
      :erlang.trace(supervisor, false, [:procs])
      assert_receive {:DOWN, ^monitor, :process, ^handler, _}, 1_000
      assert_receive {:nodechange, :down, "node-a"}, 1_000

      assert_receive %Jobs.Event{
                       type: :job_finished,
                       result: %Jobs.Result{id: ^job_id, node: "node-a", error: :nodedown}
                     },
                     1_000

      assert Storage.Nodes.list(:sys.get_state(coordinator).cluster.storage) == []

      assert Jobs.State.get_job_info(
               :sys.get_state(GenServer.whereis(jobs_server())).domain,
               job_id
             ) == nil

      # Querying the supervisor waits until all replacement children are started.
      _ = Supervisor.which_children(supervisor)
      NodeWire.Client.reconnect(client)
      assert_receive {:nodechange, :up, "node-a"}, 1_000
      assert Storage.Nodes.get(:sys.get_state(coordinator).cluster.storage, "node-a")
      assert Process.whereis(Coordinator) == coordinator
    end
  end

  defp start_agent do
    start_supervised!(
      {NodeWire.Client,
       protocols: [Exdock.Wire.V1],
       handler: Exdock.TestSupport.NativeAgent,
       handler_args: self(),
       phases: Exdock.Wire.Phases.client(),
       reconnect: [enabled: false],
       transport:
         {:tls,
          [
            host: "localhost",
            port: NodeWire.Server.port(Exdock.AgentServer),
            options: [verify: :verify_none]
          ]}}
    )
  end

  defp available_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
