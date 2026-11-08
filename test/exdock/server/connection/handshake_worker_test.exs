defmodule Exdock.Server.Connection.HandshakeWorkerTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Connection.TCPServer.HandshakeWorker
  alias Exdock.Server.Connection.HandshakePortFake

  test "reports a socket handoff timeout" do
    assert {:error, :socket_handoff_timeout} =
             HandshakeWorker.await_handoff(:server, :handler_supervisor, "auth",
               max_frame_size: 128,
               socket_handoff_timeout: 0
             )
  end

  test "closes a socket after a failed TLS handshake" do
    owner = self()

    send(self(), {:continue_handshake, :accepted_socket})

    ExUnit.CaptureLog.capture_log(fn ->
      assert {:error, {:handshake_failed, :bad_certificate}} =
               HandshakeWorker.await_handoff(:server, :handler_supervisor, "auth",
                 port: HandshakePortFake,
                 port_context: %{owner: owner, scenario: :handshake_failure},
                 max_frame_size: 128,
                 handshake_timeout: 25
               )
    end)

    assert_receive {:closed, :accepted_socket}
  end

  test "configures and transfers a handshaken socket to its handler" do
    owner = self()

    send(self(), {:continue_handshake, :accepted_socket})

    assert :ok =
             HandshakeWorker.await_handoff(:server, :handler_supervisor, "auth",
               port: HandshakePortFake,
               port_context: %{owner: owner, scenario: :success},
               max_frame_size: 128
             )

    assert_receive {:socket_options, options}
    assert options[:packet] == 4
    assert options[:packet_size] == 128
    assert options[:active] == false
    assert options[:send_timeout_close]
  end

  test "closes the accepted socket when ownership cannot move to the worker" do
    owner = self()
    task_supervisor = start_supervised!({Task.Supervisor, name: nil})

    assert {:error, {:handshake_socket_handoff_failed, :not_owner}} =
             HandshakeWorker.start(:accepted_socket, :server, :handler_supervisor, "auth",
               port: HandshakePortFake,
               port_context: %{owner: owner, scenario: :handoff_failure},
               max_frame_size: 128,
               task_supervisor: task_supervisor
             )

    assert_receive {:closed, :accepted_socket}
  end

  test "rejects and closes sockets for invalid handshake limits" do
    owner = self()

    assert {:error, {:invalid_handshake_context, {:missing_option, :max_frame_size}}} =
             HandshakeWorker.start(:accepted_socket, :server, :handler_supervisor, "auth",
               port: HandshakePortFake,
               port_context: %{owner: owner, scenario: :success}
             )

    assert_receive {:closed, :accepted_socket}
  end
end
