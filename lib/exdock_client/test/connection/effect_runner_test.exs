defmodule Exdock.Client.Connection.EffectRunnerTest do
  use ExUnit.Case, async: true

  alias Exdock.Client.Connection.EffectRunner
  alias Exdock.Client.Connection.Session
  alias Exdock.Client.Connection.State

  test "disconnect interprets transport cleanup and schedules one reconnect" do
    heartbeat_timer = make_ref()

    state =
      State.new(
        session: %Session{phase: :ready, reconnect_enabled: true},
        socket: :socket,
        heartbeat_timer: heartbeat_timer,
        reconnect_timer: nil,
        transport: __MODULE__,
        timer: __MODULE__
      )

    disconnected = EffectRunner.disconnect(state, "network error")

    assert disconnected.session.phase == :disconnected
    assert disconnected.socket == nil
    assert is_reference(disconnected.reconnect_timer)
    assert_receive {:closed, :socket}
    assert_receive {:cancelled, ^heartbeat_timer}
    assert_receive {:reconnect_scheduled, 20_000}

    assert EffectRunner.schedule_reconnect(disconnected).reconnect_timer ==
             disconnected.reconnect_timer
  end

  def close(socket) do
    send(self(), {:closed, socket})
    :ok
  end

  def cancel(timer) do
    send(self(), {:cancelled, timer})
    false
  end

  def reconnect(interval) do
    send(self(), {:reconnect_scheduled, interval})
    make_ref()
  end
end
