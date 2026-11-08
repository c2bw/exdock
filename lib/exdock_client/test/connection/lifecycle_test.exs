defmodule Exdock.Client.Connection.LifecycleTest do
  use ExUnit.Case, async: true

  alias Exdock.Client.Connection.{Lifecycle, Session}

  @client_version "1.2.3"

  test "gates timer and handshake decisions by session phase" do
    disconnected = Session.new()

    assert Lifecycle.decide({:reconnect_timeout, true}, disconnected, @client_version) == :connect
    assert Lifecycle.decide(:heartbeat, disconnected, @client_version) == :ignore
    assert Lifecycle.decide(:authenticate, disconnected, @client_version) == :ignore

    {:ok, connecting} = Session.transition(disconnected, :connect)
    {:ok, authenticating} = Session.transition(connecting, :socket_connected)

    assert Lifecycle.decide(:heartbeat, authenticating, @client_version) == :send_heartbeat
    assert Lifecycle.decide(:authenticate, authenticating, @client_version) == :authenticate
    assert Lifecycle.decide({:runtime_bundle, true}, authenticating, @client_version) == :initialize_runtime
    assert Lifecycle.decide({:runtime_bundle, false}, authenticating, @client_version) == :ignore
  end

  test "ignores stale socket events and maps current failures" do
    session = Session.new()

    assert Lifecycle.decide({:socket_frame, false}, session, @client_version) == :ignore
    assert Lifecycle.decide({:socket_closed, false}, session, @client_version) == :ignore

    assert Lifecycle.decide({:socket_closed, true}, session, @client_version) ==
             {:disconnect, "SSL connection closed", true}

    assert Lifecycle.decide({:socket_error, true, :closed}, session, @client_version) ==
             {:disconnect, "TCP error: closed", true}
  end

  test "disables reconnect for permanent server errors" do
    session = Session.new()

    assert Lifecycle.decide({:server_error, {:authentication_error, :invalid_auth}}, session, @client_version) ==
             {:disconnect, "auth_error: :invalid_auth", false}

    assert Lifecycle.decide({:server_error, :temporary_failure}, session, @client_version) ==
             {:disconnect, "server returned an error: :temporary_failure", true}
  end
end
