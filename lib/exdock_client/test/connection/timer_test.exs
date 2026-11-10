defmodule Exdock.Client.Connection.TimerTest do
  use ExUnit.Case, async: true

  alias Exdock.Client.Connection.Timer

  test "schedules heartbeat and reconnect messages for the calling process" do
    heartbeat = Timer.heartbeat(0)
    reconnect = Timer.reconnect(0)

    assert is_reference(heartbeat)
    assert is_reference(reconnect)
    assert_receive {:timeout, ^heartbeat, :wire_tick}
    assert_receive {:timeout, ^reconnect, :try_reconnect}
  end

  test "cancels an outstanding timer" do
    timer = Timer.heartbeat(60_000)

    assert is_integer(Timer.cancel(timer))
    refute_receive {:timeout, ^timer, :wire_tick}
  end
end
