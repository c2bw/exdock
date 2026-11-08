defmodule Exdock.Server.SupervisorTest do
  use Exdock.DataCase, async: false

  alias Exdock.Server.Connection.TCPServer
  alias Exdock.Server.Connection.TCPServer.{ClientRegistry, HandlerSupervisor}

  test "restarts the state owner and downstream dependencies when it crashes" do
    supervisor_pid =
      start_supervised!(
        {Exdock.Server.Supervisor,
         tcp_port: available_port(),
         auth_key: "supervisor-test-auth",
         email: "supervisor-test@example.com",
         plain_password: "supervisor-test-password"}
      )

    original_processes = backend_processes()

    downstream_names = [
      :state_owner,
      :automation_scheduler,
      :registry_client,
      :registry_fetch_limiter,
      :jobs,
      :logging,
      :notifier,
      :connection_supervisor,
      :client_registry,
      :tcp_server,
      :handler_supervisor,
      :tcp_supervisor,
      :handshake_supervisor
    ]

    monitors =
      Map.new(downstream_names, fn name ->
        {name, Process.monitor(Map.fetch!(original_processes, name))}
      end)

    Process.exit(original_processes.state_owner, :kill)

    Enum.each(downstream_names, fn name ->
      pid = Map.fetch!(original_processes, name)
      assert_receive {:DOWN, reference, :process, ^pid, _reason}, 2_000
      assert reference == Map.fetch!(monitors, name)
    end)

    _ = :sys.get_state(supervisor_pid)
    restarted_processes = backend_processes()

    assert is_pid(supervisor_pid)
    assert map_size(restarted_processes) == map_size(original_processes)
    assert Enum.all?(restarted_processes, fn {_name, pid} -> is_pid(pid) end)
    assert restarted_processes.vault == original_processes.vault
    assert restarted_processes.broadcast == original_processes.broadcast

    assert Enum.all?(downstream_names, fn name ->
             Map.fetch!(restarted_processes, name) != Map.fetch!(original_processes, name)
           end)

    assert length(Supervisor.which_children(supervisor_pid)) == 10
  end

  defp backend_processes do
    %{
      state_owner: Process.whereis(Exdock.Runtime.Coordinator),
      automation_scheduler: Process.whereis(Exdock.Server.AutomationScheduler),
      registry_client: Process.whereis(Exdock.Docker.Remote.RegistryClient),
      registry_fetch_limiter: Process.whereis(Exdock.Server.RegistryFetchLimiter),
      connection_supervisor: Process.whereis(Exdock.Server.Connection.Supervisor),
      client_registry: Process.whereis(ClientRegistry),
      tcp_server: Process.whereis(TCPServer),
      handler_supervisor: Process.whereis(HandlerSupervisor),
      tcp_supervisor: Process.whereis(TCPServer.TCPSupervisor),
      handshake_supervisor: Process.whereis(TCPServer.TaskSupervisor),
      vault: Process.whereis(Exdock.Database.Vault),
      broadcast: Process.whereis(Exdock.Server.Broadcast),
      jobs: Process.whereis(Exdock.Server.Jobs),
      logging: Process.whereis(Exdock.Server.Logging),
      notifier: Process.whereis(Exdock.Server.Notifier)
    }
  end

  defp available_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
