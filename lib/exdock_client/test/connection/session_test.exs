defmodule Exdock.Client.Connection.SessionTest do
  use ExUnit.Case, async: true

  alias Exdock.Client.Connection.Session

  test "accepts the complete connection lifecycle" do
    session = Session.new()

    assert {:ok, session} = Session.transition(session, :connect)
    assert session.phase == :connecting

    assert {:ok, session} = Session.transition(session, :socket_connected)
    assert session.phase == :authenticating
    assert Session.socket_open?(session)

    assert {:ok, session} = Session.transition(session, :runtime_bundle_received)
    assert session.phase == :initializing

    assert {:ok, session} = Session.transition(session, :ready)
    assert session.phase == :ready

    assert {:ok, session} = Session.transition(session, :disconnect)
    assert session.phase == :disconnected
    assert Session.connectable?(session)
  end

  test "rejects out-of-order lifecycle events" do
    session = Session.new()

    assert {:error, {:invalid_transition, :disconnected, :ready}} =
             Session.transition(session, :ready)

    assert {:ok, connecting} = Session.transition(session, :connect)

    assert {:error, {:invalid_transition, :connecting, :runtime_bundle_received}} =
             Session.transition(connecting, :runtime_bundle_received)
  end

  test "reconnect policy is independent from the current phase" do
    session =
      Session.new()
      |> Session.disable_reconnect()

    refute Session.reconnect_enabled?(session)
    assert {:ok, connecting} = Session.transition(session, :connect)
    refute Session.reconnect_enabled?(connecting)
  end
end
