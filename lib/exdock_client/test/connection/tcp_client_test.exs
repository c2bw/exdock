defmodule Exdock.Client.Connection.TCPClientTest do
  use ExUnit.Case, async: true
  import Kernel, except: [send: 2]

  alias Exdock.Client.Connection.Session
  alias Exdock.Client.Connection.State
  alias Exdock.Client.Connection.TCPClient
  alias Exdock.Protocol.{Channel, Message}

  test "init keeps configured host as a charlist" do
    assert {:ok, state, {:continue, :connect}} =
             TCPClient.init({"node-a", ~c"localhost", 5000, "secret"})

    assert state.host == ~c"localhost"
    assert state.session.phase == :disconnected
  end

  test "negotiation completion sends the agent hello and schedules the next session tick" do
    {client, server, done} = channels_before_client_establishment()
    timer = make_ref()

    state =
      client_state(:authenticating,
        socket: :fake_socket,
        wire: client,
        transport: __MODULE__,
        heartbeat_timer: timer,
        client_name: "node-a",
        auth_key: "token"
      )

    assert {:noreply, state} = TCPClient.handle_info({:ssl, :fake_socket, done}, state)
    assert_receive {:wire, bytes}

    assert {:ok, _, [{:hello, %{"node" => "node-a", "auth_token" => "token"}}]} =
             Channel.feed(server, bytes, &capture/1)

    assert {:noreply, ^state} = TCPClient.handle_info({:timeout, make_ref(), :wire_tick}, state)
    assert {:noreply, updated} = TCPClient.handle_info({:timeout, timer, :wire_tick}, state)
    assert is_reference(updated.heartbeat_timer)
    refute updated.heartbeat_timer == timer
  end

  test "a fragmented NodeWire command executes once after readiness" do
    {client, server} = established_channels()
    command = Message.command("job-id", "container_start", ["container"])
    assert {:ok, _, []} = Channel.send_event(server, {:command, command}, &capture/1)
    assert_receive {:wire, <<prefix::binary-size(4), rest::binary>>}

    state = client_state(:ready, socket: :fake_socket, wire: client, transport: __MODULE__, runtime_executor: __MODULE__)
    assert {:noreply, state} = TCPClient.handle_info({:ssl, :fake_socket, prefix}, state)
    refute_received {:executed, _}
    assert {:noreply, _state} = TCPClient.handle_info({:ssl, :fake_socket, rest}, state)
    assert_receive {:executed, ^command}
    refute_received {:executed, _}
  end

  test "a command before readiness disconnects without execution" do
    {client, server} = established_channels()
    command = Message.command("job-id", "container_start", ["container"])
    assert {:ok, _, []} = Channel.send_event(server, {:command, command}, &capture/1)
    assert_receive {:wire, bytes}

    state = client_state(:authenticating, socket: :fake_socket, wire: client, transport: __MODULE__, runtime_executor: __MODULE__)
    assert {:noreply, state} = TCPClient.handle_info({:ssl, :fake_socket, bytes}, state)
    assert state.socket == nil
    assert state.wire == nil
    refute_received {:executed, _}
  end

  test "an oversized result becomes a correlated terminal failure on the same session" do
    {client, server} = established_channels()
    state = client_state(:ready, socket: :fake_socket, wire: client, transport: __MODULE__)
    data = String.duplicate("x", 1_048_577)
    result = Message.result("job-id", "container_start", "node-a", data, nil)

    assert {:noreply, state} = TCPClient.handle_cast({:client_message, {:result, result}}, state)
    assert state.socket == :fake_socket
    assert_receive {:wire, bytes}

    assert {:ok, _, [{:result, %{"id" => "job-id", "data" => nil, "error" => error}}]} =
             Channel.feed(server, bytes, &capture/1)

    assert is_binary(error)
  end

  test "repeated disconnects keep a single reconnect timer" do
    state = client_state()

    assert {:noreply, disconnected_state} =
             TCPClient.handle_info({:ssl_closed, state.socket}, state)

    assert is_reference(disconnected_state.reconnect_timer)
    assert disconnected_state.session.phase == :disconnected

    assert {:noreply, repeatedly_disconnected_state} =
             TCPClient.handle_info({:ssl_closed, state.socket}, disconnected_state)

    assert repeatedly_disconnected_state.reconnect_timer == disconnected_state.reconnect_timer

    Process.cancel_timer(disconnected_state.reconnect_timer)
  end

  test "only the current reconnect timer can start a connection attempt" do
    state = client_state()

    assert {:noreply, disconnected_state} =
             TCPClient.handle_info({:ssl_closed, state.socket}, state)

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

  test "an authentication error closes the connection without scheduling reconnect" do
    {client, server} = established_channels()
    assert {:ok, _, []} = Channel.send_event(server, {:error, :invalid_auth}, &capture/1)
    assert_receive {:wire, bytes}

    state = client_state(:authenticating, socket: :fake_socket, wire: client, transport: __MODULE__)
    assert {:noreply, stopped_state} = TCPClient.handle_info({:ssl, :fake_socket, bytes}, state)
    refute Session.reconnect_enabled?(stopped_state.session)
    assert stopped_state.reconnect_timer == nil
    assert stopped_state.socket == nil
  end

  defp client_state(attrs \\ []) when is_list(attrs),
    do: client_state(:disconnected, attrs)

  defp client_state(phase, attrs) do
    session = %Session{phase: phase, reconnect_enabled: true}
    State.new(Keyword.put(attrs, :session, session))
  end

  defp established_channels do
    {client, server, done} = channels_before_client_establishment()
    assert {:ok, client, [:established]} = Channel.feed(client, done, &capture/1)
    {client, server}
  end

  defp channels_before_client_establishment do
    assert {:ok, client, []} = Channel.start(:client, &capture/1)
    assert {:ok, server, []} = Channel.start(:server, &capture/1)
    assert_receive {:wire, hello}
    assert {:ok, server, []} = Channel.feed(server, hello, &capture/1)
    assert_receive {:wire, select}
    assert {:ok, client, []} = Channel.feed(client, select, &capture/1)
    assert_receive {:wire, ready}
    assert {:ok, server, [:established]} = Channel.feed(server, ready, &capture/1)
    assert_receive {:wire, done}
    {client, server, done}
  end

  def activate(_socket), do: :ok
  def close(_socket), do: :ok
  def send(:fake_socket, bytes), do: capture(bytes)

  defp capture(bytes) do
    Kernel.send(self(), {:wire, bytes})
    :ok
  end

  def execute(command) do
    Kernel.send(self(), {:executed, command})
    :ok
  end
end
