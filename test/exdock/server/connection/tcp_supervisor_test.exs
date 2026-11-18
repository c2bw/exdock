defmodule Exdock.Server.Connection.TCPSupervisorTest do
  use ExUnit.Case, async: false
  alias Exdock.Server.Connection

  defp start_server do
    start_supervised!({Connection.Supervisor, {"test-auth-token", 0}})
    NodeWire.Server.port(Exdock.AgentServer)
  end

  defp tls(port) do
    :ssl.connect(
      ~c"localhost",
      port,
      [
        verify: :verify_none,
        active: false,
        mode: :binary,
        packet: 4,
        server_name_indication: ~c"localhost",
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ],
      1000
    )
  end

  defp connect(port) do
    {:ok, socket} = tls(port)

    hello =
      NodeWire.Negotiation.hello([Exdock.Wire.V1], [], %{
        "node" => "bounded",
        "agent_version" => Exdock.Protocol.Compatibility.agent_version(),
        "auth_token" => :crypto.hash(:sha256, "test-auth-token") |> Base.encode16()
      })

    :ok = :ssl.send(socket, NodeWire.Control.encode(:hello, hello))
    {:ok, accept} = :ssl.recv(socket, 0, 1000)
    {:ok, :accept, _} = NodeWire.Control.decode(accept)
    {:ok, _bundle} = :ssl.recv(socket, 0, 1000)
    {:ok, conn} = NodeWire.Server.connection(Exdock.AgentServer, "bounded")
    {socket, conn.owner}
  end

  test "generates a fresh self-signed certificate on each server startup" do
    port = start_server()
    {:ok, socket} = tls(port)
    {:ok, first_certificate} = :ssl.peercert(socket)
    assert :public_key.pkix_is_self_signed(first_certificate)
    :ok = :ssl.close(socket)
    :ok = stop_supervised(Connection.Supervisor)

    port = start_server()
    {:ok, socket} = tls(port)
    {:ok, next_certificate} = :ssl.peercert(socket)
    assert :public_key.pkix_is_self_signed(next_certificate)
    refute first_certificate == next_certificate
    :ok = :ssl.close(socket)
  end

  test "a stalled TLS handshake does not block later clients" do
    port = start_server()
    {:ok, stalled} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false], 1000)
    {socket, owner} = connect(port)
    monitor = Process.monitor(owner)
    :ssl.close(socket)
    assert_receive {:DOWN, ^monitor, :process, ^owner, _}, 1000
    :gen_tcp.close(stalled)
  end

  test "native owners use bounded passive-handoff packet4 sockets" do
    port = start_server()
    {socket, owner} = connect(port)
    state = :sys.get_state(owner)
    supervisor = NodeWire.Server.child(Exdock.AgentServer, DynamicSupervisor)

    assert Enum.any?(DynamicSupervisor.which_children(supervisor), fn {_, pid, _, _} ->
             pid == owner
           end)

    {:ok, options} =
      :ssl.getopts(state.socket, [
        :active,
        :packet,
        :packet_size,
        :send_timeout,
        :send_timeout_close
      ])

    assert options[:active] == :once
    assert options[:packet] == 4
    assert options[:packet_size] == 16_777_216
    assert options[:send_timeout_close]
    :ssl.close(socket)
  end

  test "oversized bootstrap packets are closed before authentication" do
    port = start_server()
    {:ok, socket} = tls(port)
    :ok = :ssl.send(socket, :binary.copy(<<0>>, 16_385))
    assert {:error, _} = :ssl.recv(socket, 0, 1000)
    assert NodeWire.Server.connections(Exdock.AgentServer) == []
    :ssl.close(socket)
  end
end
