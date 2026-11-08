defmodule Exdock.Client.Connection.TransitionTest do
  use ExUnit.Case, async: true

  alias Exdock.Client.Connection.{Session, State, Transition}

  test "disconnect describes cleanup and reconnect effects without executing them" do
    heartbeat_timer = make_ref()

    state =
      State.new(
        session: %Session{phase: :ready, reconnect_enabled: true},
        socket: :socket,
        heartbeat_timer: heartbeat_timer,
        reconnect_timer: nil
      )

    assert {disconnected, effects} = Transition.disconnect(state, "network error")
    assert disconnected.session.phase == :disconnected
    assert disconnected.socket == nil
    assert disconnected.heartbeat_timer == nil

    assert effects == [
             {:log_disconnection, "network error", true},
             {:close_socket, :socket},
             {:cancel_timer, heartbeat_timer},
             :schedule_reconnect
           ]
  end

  test "non-retriable disconnect disables reconnect and cancels its timer" do
    reconnect_timer = make_ref()

    state = State.new(session: Session.new(), reconnect_timer: reconnect_timer)

    assert {disconnected, effects} = Transition.disconnect(state, "invalid auth", false)
    refute Session.reconnect_enabled?(disconnected.session)
    assert disconnected.reconnect_timer == nil
    assert {:cancel_timer, reconnect_timer} in effects
    refute :schedule_reconnect in effects
  end
end
