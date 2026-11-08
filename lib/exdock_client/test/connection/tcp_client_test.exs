defmodule Exdock.Client.Connection.TCPClientTest do
  use ExUnit.Case, async: true

  alias Exdock.Client.Connection.Session
  alias Exdock.Client.Connection.State
  alias Exdock.Client.Connection.TCPClient
  alias Exdock.Protocol.{Contract, Message}

  test "init keeps configured host as a charlist" do
    assert {:ok, state, {:continue, :connect}} =
             TCPClient.init({"node-a", ~c"localhost", 5000, "secret"})

    assert state.host == ~c"localhost"
    assert state.session.phase == :disconnected
  end

  test "malformed server frames become protocol errors without crashing the client" do
    state = client_state(socket: :fake_socket)

    assert {:noreply, ^state} = TCPClient.handle_info({:ssl, :fake_socket, <<3>>}, state)
    assert_receive {:server_error, :malformed_message}
  end

  test "legacy arbitrary RPC frames are rejected without execution" do
    message = <<2, 12, :erlang.term_to_binary({__MODULE__, :raise_from_remote_call, [self()]})::binary>>
    state = client_state(socket: :fake_socket)

    assert {:noreply, ^state} = TCPClient.handle_info({:ssl, :fake_socket, message}, state)
    assert_receive {:server_error, {:version_mismatch, :version_too_old}}
    refute_receive {:remote_call_started, _pid}
  end

  test "commands execute through the runtime boundary stored in client state" do
    command = Message.command("job-id", "container_start", ["container"])
    frame = Contract.encode_term_frame(:command, command)
    state = client_state(socket: :fake_socket, runtime_executor: __MODULE__)

    assert {:noreply, ^state} = TCPClient.handle_info({:ssl, :fake_socket, frame}, state)
    assert_receive {:executed, ^command}
  end

  test "repeated disconnects keep a single reconnect timer" do
    state = client_state()

    assert {:noreply, disconnected_state} =
             TCPClient.handle_info({:server_error, :temporary_failure}, state)

    assert is_reference(disconnected_state.reconnect_timer)
    assert disconnected_state.session.phase == :disconnected

    assert {:noreply, repeatedly_disconnected_state} =
             TCPClient.handle_info({:server_error, :another_temporary_failure}, disconnected_state)

    assert repeatedly_disconnected_state.reconnect_timer == disconnected_state.reconnect_timer

    Process.cancel_timer(disconnected_state.reconnect_timer)
  end

  test "only the current reconnect timer can start a connection attempt" do
    state = client_state()

    assert {:noreply, disconnected_state} =
             TCPClient.handle_info({:server_error, :temporary_failure}, state)

    reconnect_timer = disconnected_state.reconnect_timer
    stale_timer = make_ref()

    assert {:noreply, ^disconnected_state} =
             TCPClient.handle_info({:timeout, stale_timer, :try_reconnect}, disconnected_state)

    assert {:noreply, reconnecting_state, {:continue, :connect}} =
             TCPClient.handle_info({:timeout, reconnect_timer, :try_reconnect}, disconnected_state)

    assert reconnecting_state.reconnect_timer == nil

    Process.cancel_timer(reconnect_timer)
  end

  test "stale reconnect and socket messages are ignored after connecting" do
    state = client_state(:ready, socket: :current_socket)

    assert {:noreply, ^state} =
             TCPClient.handle_info({:timeout, make_ref(), :try_reconnect}, state)

    assert {:noreply, ^state} = TCPClient.handle_info({:ssl_closed, :stale_socket}, state)
    assert {:noreply, ^state} = TCPClient.handle_info({:ssl_error, :stale_socket, :closed}, state)
    assert {:noreply, ^state} = TCPClient.handle_info({:ssl, :stale_socket, <<>>}, state)
    assert {:noreply, ^state} = TCPClient.handle_continue(:connect, state)
  end

  test "stale runtime bundles cannot move a ready connection backwards" do
    state = client_state(:ready, socket: :current_socket)

    assert {:noreply, ^state} =
             TCPClient.handle_info(
               {:runtime_bundle, %{"version" => "stale"}, :stale_socket},
               state
             )

    assert {:noreply, ^state} =
             TCPClient.handle_info(
               {:runtime_bundle, %{"version" => "duplicate"}, :current_socket},
               state
             )
  end

  test "non-retriable server errors cancel a pending reconnect" do
    state = client_state()

    assert {:noreply, disconnected_state} =
             TCPClient.handle_info({:server_error, :temporary_failure}, state)

    reconnect_timer = disconnected_state.reconnect_timer

    assert {:noreply, stopped_state} =
             TCPClient.handle_info(
               {:server_error, {:authentication_error, :invalid_auth}},
               disconnected_state
             )

    refute Session.reconnect_enabled?(stopped_state.session)
    assert stopped_state.reconnect_timer == nil
    refute_received {:timeout, ^reconnect_timer, :try_reconnect}
  end

  defp client_state(attrs \\ []) when is_list(attrs),
    do: client_state(:disconnected, attrs)

  defp client_state(phase, attrs) do
    session = %Session{phase: phase, reconnect_enabled: true}
    State.new(Keyword.put(attrs, :session, session))
  end

  def execute(command) do
    send(self(), {:executed, command})
    :ok
  end
end
