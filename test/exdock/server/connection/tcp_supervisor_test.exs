defmodule Exdock.Server.Connection.TCPSupervisorTest do
  use ExUnit.Case, async: false

  alias Exdock.Server.Connection
  alias Exdock.Server.Connection.TCPServer
  alias Exdock.Server.Connection.TCPServer.HandlerSupervisor

  test "a stalled TLS handshake does not block later clients" do
    port = available_port()
    start_supervised!({Connection.Supervisor, {"test-auth-token", port, max_frame_size: 128}})

    task_supervisor = Process.whereis(TCPServer.TaskSupervisor)
    assert :erlang.trace(task_supervisor, true, [:procs]) == 1

    assert {:ok, stalled_socket} =
             :gen_tcp.connect(~c"localhost", port, [:binary, active: false], 1_000)

    assert_receive {:trace, ^task_supervisor, :spawn, handshake_worker, _mfa}, 1_000
    assert :erlang.trace(task_supervisor, false, [:procs]) == 1
    worker_monitor = Process.monitor(handshake_worker)

    {client_socket, handler_pid} = connect_supervised_handler(port)
    handler_monitor = Process.monitor(handler_pid)

    :ssl.close(client_socket)
    assert_receive {:DOWN, ^handler_monitor, :process, ^handler_pid, _reason}, 1_000

    ExUnit.CaptureLog.capture_log(fn ->
      :ok = :gen_tcp.close(stalled_socket)
      assert_receive {:DOWN, ^worker_monitor, :process, ^handshake_worker, _reason}, 1_000
    end)
  end

  test "hands bounded sockets to dynamically supervised handlers" do
    port = available_port()
    start_supervised!({Connection.Supervisor, {"test-auth-token", port, max_frame_size: 128}})

    {client_socket, handler_pid} = connect_supervised_handler(port)
    state = :sys.get_state(handler_pid)

    assert Enum.any?(
             DynamicSupervisor.which_children(HandlerSupervisor),
             fn {_id, pid, _type, _modules} -> pid == handler_pid end
           )

    assert {:ok, socket_options} =
             :ssl.getopts(
               state.socket,
               [:active, :packet, :packet_size, :send_timeout, :send_timeout_close]
             )

    assert socket_options[:active] == :once
    assert socket_options[:packet] == 4
    assert socket_options[:packet_size] == 128
    assert socket_options[:send_timeout] == 5_000
    assert socket_options[:send_timeout_close]

    :ssl.close(client_socket)
  end

  test "disconnects clients that exceed the maximum frame size" do
    port = available_port()
    start_supervised!({Connection.Supervisor, {"test-auth-token", port, max_frame_size: 128}})

    {client_socket, handler_pid} = connect_supervised_handler(port)
    _ = :sys.get_state(handler_pid)
    monitor_ref = Process.monitor(handler_pid)

    ExUnit.CaptureLog.capture_log(fn ->
      assert :ok = :ssl.send(client_socket, :binary.copy(<<0>>, 129))
      assert_receive {:DOWN, ^monitor_ref, :process, ^handler_pid, _reason}, 1_000
    end)

    :ssl.close(client_socket)
  end

  defp connect_supervised_handler(port) do
    handler_supervisor = Process.whereis(HandlerSupervisor)
    task_supervisor = Process.whereis(TCPServer.TaskSupervisor)
    assert :erlang.trace(handler_supervisor, true, [:procs]) == 1
    assert :erlang.trace(task_supervisor, true, [:procs, :set_on_spawn]) == 1

    assert {:ok, client_socket} =
             :ssl.connect(
               ~c"localhost",
               port,
               [verify: :verify_none, active: false, packet: 4],
               1_000
             )

    assert_receive {:trace, ^task_supervisor, :spawn, handshake_worker, _mfa}, 1_000
    worker_monitor = Process.monitor(handshake_worker)
    assert_receive {:trace, ^handler_supervisor, :spawn, handler_pid, _mfa}, 1_000
    assert :erlang.trace(handler_supervisor, false, [:procs]) == 1
    assert :erlang.trace(task_supervisor, false, [:procs, :set_on_spawn]) == 1
    # TLS connect may return after the handoff worker has already exited. Its
    # inherited trace proves a normal exit even if the later monitor sees noproc.
    assert_receive {:trace, ^handshake_worker, :exit, :normal}, 1_000

    assert_receive {:DOWN, ^worker_monitor, :process, ^handshake_worker, reason}
                   when reason in [:normal, :noproc],
                   1_000

    {client_socket, handler_pid}
  end

  defp available_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
