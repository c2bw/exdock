defmodule Exdock.Client.Connection.HandshakeTest do
  use ExUnit.Case, async: true
  import Kernel, except: [send: 2]

  alias Exdock.Client.Connection.Handshake
  alias Exdock.Client.Connection.Session
  alias Exdock.Client.Connection.State

  test "connect opens the socket, advances the session, and schedules authentication" do
    Process.put(:connect_result, {:ok, :socket})

    assert {:ok, connected} = Handshake.connect(state())
    assert connected.socket == :socket
    assert connected.session.phase == :authenticating
    assert is_reference(connected.heartbeat_timer)

    assert_receive {:connect, ~c"localhost", 5000, options, 3_000}
    assert options[:verify] == :verify_none
    assert_receive {:heartbeat_scheduled, 10_000}
    assert_receive :authenticate_client
  end

  test "failed connections return to disconnected state with one reconnect timer" do
    Process.put(:connect_result, {:error, :econnrefused})

    assert {:error, disconnected} = Handshake.connect(state())
    assert disconnected.session.phase == :disconnected
    assert disconnected.socket == nil
    assert is_reference(disconnected.reconnect_timer)
    assert_receive {:reconnect_scheduled, 20_000}
  end

  test "authentication sends the canonical hello frame" do
    state = %{state() | socket: :socket, session: %Session{phase: :authenticating, reconnect_enabled: true}}

    assert Handshake.authenticate(state, "1.2.3") == state
    assert_receive {:sent, :socket, frame}
    assert is_binary(frame)
  end

  test "authentication disconnects after a transport failure" do
    Process.put(:send_result, {:error, :closed})
    state = %{state() | socket: :socket, session: %Session{phase: :authenticating, reconnect_enabled: true}}

    disconnected = Handshake.authenticate(state, "1.2.3")

    assert disconnected.session.phase == :disconnected
    assert disconnected.socket == nil
    assert is_reference(disconnected.reconnect_timer)
    assert_receive {:closed, :socket}
    assert_receive {:reconnect_scheduled, 20_000}
  end

  test "heartbeat and client messages are no-ops without a socket" do
    state = state()

    assert Handshake.heartbeat(state) == state
    assert Handshake.send_client_message(state, {:heartbeat}) == state
    refute_receive {:sent, _, _}
  end

  test "successful heartbeat schedules the next tick" do
    state = %{state() | socket: :socket}

    updated = Handshake.heartbeat(state)

    assert is_reference(updated.heartbeat_timer)
    assert_receive {:sent, :socket, _frame}
    assert_receive {:heartbeat_scheduled, 10_000}
  end

  test "old runtime messages are suppressed until the new connection is ready" do
    for phase <- [:disconnected, :authenticating, :initializing] do
      state = %{state() | socket: :socket, session: %Session{phase: phase, reconnect_enabled: true}}
      assert Handshake.send_client_message(state, {:heartbeat}) == state
      refute_receive {:sent, _, _}, 0
    end

    state = %{state() | socket: :socket, session: %Session{phase: :ready, reconnect_enabled: true}}
    assert Handshake.send_client_message(state, {:heartbeat}) == state
    assert_receive {:sent, :socket, _}
  end

  def connect(host, port, options, timeout) do
    Kernel.send(self(), {:connect, host, port, options, timeout})
    Process.get(:connect_result) || raise "missing connect result"
  end

  def send(socket, frame) do
    Kernel.send(self(), {:sent, socket, frame})
    Process.get(:send_result, :ok)
  end

  def close(socket) do
    Kernel.send(self(), {:closed, socket})
    :ok
  end

  def heartbeat(interval) do
    Kernel.send(self(), {:heartbeat_scheduled, interval})
    make_ref()
  end

  def reconnect(interval) do
    Kernel.send(self(), {:reconnect_scheduled, interval})
    make_ref()
  end

  def cancel(_timer), do: false

  defp state do
    State.new(
      host: ~c"localhost",
      port: 5000,
      client_name: "node-a",
      auth_key: "token",
      session: Session.new(),
      transport: __MODULE__,
      timer: __MODULE__
    )
  end
end
