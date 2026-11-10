defmodule Exdock.Server.Connection.TCPSupervisorTest do
  use ExUnit.Case, async: false

  alias Exdock.Protocol.{Channel, Compatibility, Message, Payload}
  alias Exdock.Protocol.Messages.{JobResult, Update}
  alias Exdock.Server.Connection
  alias Exdock.Server.Connection.Handler
  alias Exdock.Server.Jobs.Job
  alias Exdock.Server.Connection.TCPServer
  alias Exdock.Server.Connection.TCPServer.HandlerSupervisor

  test "a stalled TLS handshake does not block later clients" do
    port = available_port()
    start_supervised!({Connection.Supervisor, {"test-auth-token", port, max_frame_size: 1024}})

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
    start_supervised!({Connection.Supervisor, {"test-auth-token", port, max_frame_size: 1024}})

    {client_socket, handler_pid} = connect_supervised_handler(port)
    state = :sys.get_state(handler_pid)

    assert Enum.any?(
             DynamicSupervisor.which_children(HandlerSupervisor),
             fn {_id, pid, _type, _modules} -> pid == handler_pid end
           )

    assert {:ok, socket_options} =
             :ssl.getopts(
               state.socket,
               [:active, :packet, :send_timeout, :send_timeout_close]
             )

    assert socket_options[:active] == :once
    assert socket_options[:packet] in [0, :raw]
    assert socket_options[:send_timeout] == 5_000
    assert socket_options[:send_timeout_close]

    :ssl.close(client_socket)
  end

  test "disconnects peers using an incompatible frame format" do
    port = available_port()
    start_supervised!({Connection.Supervisor, {"test-auth-token", port, max_frame_size: 1024}})

    {client_socket, handler_pid} = connect_supervised_handler(port)
    _ = :sys.get_state(handler_pid)
    monitor_ref = Process.monitor(handler_pid)

    ExUnit.CaptureLog.capture_log(fn ->
      assert :ok = :ssl.send(client_socket, :binary.copy(<<0>>, 129))
      assert_receive {:DOWN, ^monitor_ref, :process, ^handler_pid, _reason}, 1_000
    end)

    :ssl.close(client_socket)
  end

  test "negotiates over TLS and routes coalesced progress and result events to the dispatched job" do
    port = available_port()
    start_supervised!({Connection.Supervisor, {"test-auth-token", port}})

    {socket, handler} = connect_supervised_handler(port)
    on_exit(fn -> :ssl.close(socket) end)
    assert :erlang.trace(handler, true, [:send]) == 1
    write = &:ssl.send(socket, &1)

    assert {:ok, wire, []} =
             Channel.start(:client, fn <<prefix::binary-size(3), suffix::binary>> ->
               :ok = write.(prefix)
               write.(suffix)
             end)

    {wire, [:established]} = recv_events(socket, wire)
    version = Compatibility.agent_version()
    token = :crypto.hash(:sha256, "test-auth-token") |> Base.encode16()
    hello = %{"agent_version" => version, "auth_token" => token, "node" => "test-node"}

    assert {:ok, wire, []} = Channel.send_event(wire, {:hello, hello}, write)
    {wire, [{:runtime_bundle, payload}]} = recv_events(socket, wire)
    assert {:ok, bundle} = Payload.decode(:runtime_bundle, payload)

    ready = %{
      "bundle_version" => bundle["version"],
      "digest" => bundle["digest"],
      "metadata" => %{
        "platform" => "linux/amd64",
        "agent_version" => version,
        "elixir_version" => System.version(),
        "otp_release" => System.otp_release()
      }
    }

    assert {:ok, wire, []} = Channel.send_event(wire, {:ready, ready}, write)
    assert_receive {:trace, ^handler, :send, {:client_ready, ^handler, "test-node", _}, _}, 1_000

    job = %Job{id: "tls-job", name: :container_start, parameters: ["container"]}
    assert :ok = Handler.send_command(handler, job)
    {wire, events} = recv_events(socket, wire)
    assert {:command, Message.command(job.id, job.name, job.parameters)} in events

    progress = Message.progress(job.id, "container_start", "test-node", "starting")
    result = Message.result(job.id, "container_start", "test-node", "container", nil)
    capture = fn bytes -> send(self(), {:wire_bytes, bytes}) end

    write_later = fn bytes ->
      capture.(bytes)
      :ok
    end

    assert {:ok, wire, []} = Channel.send_event(wire, {:progress, progress}, write_later)
    assert {:ok, _wire, []} = Channel.send_event(wire, {:result, result}, write_later)
    assert_receive {:wire_bytes, progress_bytes}
    assert_receive {:wire_bytes, result_bytes}
    assert :ok = write.(progress_bytes <> result_bytes)

    assert_receive {:trace, ^handler, :send, {:"$gen_cast", {:client_message, ^handler, "test-node", %Update{}}}, _},
                   1_000

    assert_receive {:trace, ^handler, :send, {:"$gen_cast", {:client_message, ^handler, "test-node", %JobResult{job: ^job}}}, _},
                   1_000

    refute Map.has_key?(:sys.get_state(handler).remote_jobs.entries, job.id)
  end

  defp recv_events(socket, wire) do
    assert {:ok, bytes} = :ssl.recv(socket, 0, 1_000)
    assert {:ok, wire, events} = Channel.feed(wire, bytes, &:ssl.send(socket, &1))
    if events == [], do: recv_events(socket, wire), else: {wire, events}
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
               [:binary, verify: :verify_none, active: false, packet: :raw],
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
