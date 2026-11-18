# Compile the standalone agent adapters in this test VM, without requiring a
# previous agent build or starting its application. Production builds stay separate.
client_source = Path.expand("../../../../../lib/exdock_client/lib/connection", __DIR__)
files = ["metadata.ex", "runtime_executor.ex", "runtime_installer.ex"] |> Enum.map(&Path.join(client_source, &1))

files =
  files ++
    Path.wildcard(Path.join(client_source, "runtime_installer/**/*.ex")) ++ Path.wildcard(Path.join(client_source, "native/*.ex"))

{:ok, _, _} = Kernel.ParallelCompiler.compile(files, return_diagnostics: true)

defmodule Exdock.NativeTestInstaller do
  use GenServer

  def start_link(test),
    do: GenServer.start_link(__MODULE__, test, name: Exdock.Client.Connection.RuntimeInstaller)

  def init(test), do: {:ok, %{test: test, owner: nil}}

  def handle_call({:install, bundle, _, _}, {owner, _}, s) do
    :ok =
      Exdock.Protocol.RuntimeBundle.validate(
        bundle,
        &Exdock.Client.Connection.RuntimeInstaller.allowed_module?/1
      )

    send(s.test, {:installed, owner})
    {:reply, :ok, %{s | owner: owner}}
  end

  def handle_call(:owner, _, s), do: {:reply, s.owner, s}
end

defmodule Exdock.NativeTestExecutor do
  def execute(
        %{"id" => id, "kind" => "node_refresh", "args" => [%{"retrieve_resources" => false}]} =
          command
      ) do
    {:ok, _} = Exdock.Protocol.Command.decode(command)
    bridge = GenServer.call(Exdock.Client.Connection.RuntimeInstaller, :owner)

    GenServer.cast(
      bridge,
      {:client_message, {:progress, Exdock.Protocol.Message.progress(id, "node_refresh", "native-node", %{})}}
    )

    data = %{
      "containers" => %{"ok" => [], "errored" => []},
      "images" => %{"ok" => [], "errored" => []}
    }

    GenServer.cast(
      bridge,
      {:client_message, {:result, Exdock.Protocol.Message.result(id, "node_refresh", "native-node", data, nil)}}
    )
  end
end

defmodule Exdock.NativeLoopbackTest do
  use ExUnit.Case
  alias Exdock.Server.Connection.Native.Handler

  test "actual Exdock adapters exchange validated bundle, ready, command, progress and correlated result" do
    {certificate, key} = Exdock.Server.Connection.SelfCert.generate()
    start_supervised!({Exdock.NativeTestInstaller, self()})

    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: Exdock.Client.Connection.RuntimeBridges})

    start_supervised!({Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor})
    # Domain coordinator messages are observed without executing Docker operations.
    Process.register(self(), Exdock.Runtime.Coordinator)
    token = :crypto.hash(:sha256, "secret") |> Base.encode16()

    server =
      start_supervised!(
        {NodeWire.Server,
         protocols: [Exdock.Wire.V1],
         handler: Handler,
         handler_args: %{token: token, observer: self()},
         phases: Exdock.Wire.Phases.server(),
         lifecycle_observer: self(),
         transport:
           {:tls,
            [
              port: 0,
              options: [
                cert: certificate,
                key: key
              ]
            ]}}
      )

    client =
      start_supervised!(
        {NodeWire.Client,
         protocols: [Exdock.Wire.V1],
         handler: Exdock.Client.Connection.Native.Handler,
         handler_args: %{
           node: "native-node",
           token: token,
           runtime_executor: Exdock.NativeTestExecutor
         },
         phases: Exdock.Wire.Phases.client(),
         transport:
           {:tls,
            [
              host: "localhost",
              port: NodeWire.Server.port(server),
              options: [
                verify: :verify_none
              ]
            ]},
         reconnect: [enabled: true, interval_ms: 50]}
      )

    assert_receive {:installed, bridge}, 3000
    assert_receive {:nodewire, :ready, conn, nil}, 3000
    assert {:ok, _} = :sys.get_state(bridge) |> then(&{:ok, &1})

    job = %Exdock.Server.Jobs.Job{
      id: "native-job",
      name: :node_refresh,
      parameters: [%{"retrieve_resources" => false}]
    }

    command = Exdock.Protocol.Message.command(job.id, job.name, job.parameters)

    assert :ok =
             NodeWire.Server.send(server, "native-node", {:command, command}, on_sent: {:track_job, job})

    assert_receive {:"$gen_cast", {:client_message, _, "native-node", %Exdock.Protocol.Messages.Update{}}},
                   2000

    assert_receive {:"$gen_cast", {:client_message, _, "native-node", %Exdock.Protocol.Messages.JobResult{job: tracked}}},
                   2000

    assert tracked.id == job.id
    assert is_integer(tracked.refresh_generation)
    old = NodeWire.Client.status(client).connection
    bridge_monitor = Process.monitor(bridge)
    Process.exit(conn.owner, :kill)
    assert_receive {:nodewire, :disconnected, _, _}, 1000
    assert_receive {:DOWN, ^bridge_monitor, :process, ^bridge, _}, 2000
    assert_receive {:installed, new_bridge}, 3000
    refute new_bridge == bridge
    assert_receive {:nodewire, :ready, next, nil}, 3000
    refute next.id == conn.id

    assert {:error, :stale_connection} =
             NodeWire.Connection.notify(old, {:runtime_installed, {:ok, %{}}})
  end
end
