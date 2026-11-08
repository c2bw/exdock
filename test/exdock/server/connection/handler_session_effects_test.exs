defmodule Exdock.Server.Connection.Handler.SessionEffectsTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Connection.Handler.{SessionEffects, State}
  alias Exdock.Server.Connection.{RuntimeBundleProvider, Session}

  test "heartbeat replaces the previous timeout" do
    previous_timer = Process.send_after(self(), :stale_heartbeat, 60_000)
    state = %{State.new(self(), "auth", :socket) | heartbeat_timer: previous_timer}

    assert {:noreply, updated} = SessionEffects.interpret(:heartbeat, state, :socket, <<>>)
    assert is_reference(updated.heartbeat_timer)
    refute updated.heartbeat_timer == previous_timer

    Process.cancel_timer(updated.heartbeat_timer)
  end

  test "terminal routing reasons stop the session unchanged" do
    state = State.new(self(), "auth", :socket)

    for reason <- [:version_too_old, :version_too_new, :unauthorized, :unexpected_message] do
      assert {:stop, ^reason, ^state} = SessionEffects.interpret({:stop, reason}, state, :socket, <<>>)
    end
  end

  test "transport exceptions become explicit send errors" do
    assert {:error, {_kind, _reason}} = SessionEffects.send_message(:not_an_ssl_socket, :heartbeat)
  end

  test "authentication failures are translated into stop reasons" do
    state = State.new(self(), "token", :socket)

    assert {:stop, :invalid_auth, _state} =
             SessionEffects.interpret({:authenticate, "1.1.0", "wrong", "node-a"}, state, :socket, <<>>)

    assert {:stop, {:version_requirement, _requirement}, _state} =
             SessionEffects.interpret({:authenticate, "0.0.1", "token", "node-a"}, state, :socket, <<>>)
  end

  test "initialization rejects a runtime bundle that was not offered" do
    session =
      Session.new()
      |> Session.identify("node-a")
      |> Session.authenticate()
      |> Session.offer_bundle("expected-digest")

    state = %{State.new(self(), "token", :socket) | session: session}

    assert {:stop, :runtime_bundle_mismatch, ^state} =
             SessionEffects.interpret(
               {:initialize, RuntimeBundleProvider.version(), "wrong-digest", %{}},
               state,
               :socket,
               <<>>
             )
  end

  test "unknown and malformed frames stop cleanly even without peer metadata" do
    state = State.new(self(), "token", :socket)

    assert {:stop, :unknown_message_type, ^state} =
             SessionEffects.interpret({:stop, :unknown_message_type}, state, :socket, "unknown")

    assert {:stop, :malformed_message, ^state} =
             SessionEffects.interpret({:stop, :malformed_message}, state, :socket, "bad")
  end
end
