defmodule Exdock.Server.BroadcastTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Broadcast

  setup do
    broadcast = start_supervised!({Broadcast, name: nil})
    Exdock.Events.subscribe(:activity)
    %{broadcast: broadcast}
  end

  test "broadcasts logging status updates", %{broadcast: broadcast} do
    status = %{latest_job: "Refresh", latest_job_message: "OK"}

    assert :ok = Broadcast.broadcast(broadcast, :status, status, force: true)
    assert_receive {:exdock_event, :activity, _revision, %{source: :status, data: ^status}}
  end

  test "broadcasts logging log updates", %{broadcast: broadcast} do
    logs = [%{message_id: :node_connected, message_data: :node_a}]

    assert :ok = Broadcast.broadcast(broadcast, :log, logs, force: true)
    assert_receive {:exdock_event, :activity, _revision, %{source: :log, data: ^logs}}
  end

  test "queues and replaces immediate messages while the refresh window is closed", %{broadcast: broadcast} do
    first = %{value: 1}
    replacement = %{value: 2}

    assert :ok = Broadcast.broadcast(broadcast, :status, first, force: true)
    assert_receive {:exdock_event, :activity, _revision, %{source: :status, data: ^first}}
    assert :ok = Broadcast.broadcast(broadcast, :status, first, [])
    assert :ok = Broadcast.broadcast(broadcast, :status, replacement, [])

    assert_receive {:exdock_event, :activity, _revision, %{source: :status, data: ^replacement}}, 200
    refute_receive {:exdock_event, :activity, _revision, %{source: :status, data: ^first}}
  end

  test "delayed broadcasts keep only the latest payload", %{broadcast: broadcast} do
    initial = %{value: 1}
    replacement = %{value: 2}

    assert :ok = Broadcast.broadcast(broadcast, :status, initial, delayed: true, delay_ms: 20)
    assert :ok = Broadcast.broadcast(broadcast, :status, replacement, delayed: true, delay_ms: 20)

    assert_receive {:exdock_event, :activity, _revision, %{source: :status, data: ^replacement}}, 200
    refute_receive {:exdock_event, :activity, _revision, %{source: :status, data: ^initial}}
  end

  test "immediate broadcast overrides any pending delayed payload for the same type", %{broadcast: broadcast} do
    delayed = %{value: 1}
    immediate = %{value: 2}

    assert :ok = Broadcast.broadcast(broadcast, :status, delayed, delayed: true, delay_ms: 30)
    assert :ok = Broadcast.broadcast(broadcast, :status, immediate, [])

    assert_receive {:exdock_event, :activity, _revision, %{source: :status, data: ^immediate}}
    refute_receive {:exdock_event, :activity, _revision, %{source: :status, data: ^delayed}}, 200
  end

  test "a stale delayed timer does not release a newly staged payload", %{broadcast: broadcast} do
    old_delayed = %{value: 1}
    immediate = %{value: 2}
    new_delayed = %{value: 3}

    assert :ok = Broadcast.broadcast(broadcast, :status, old_delayed, delayed: true, delay_ms: 20)
    assert :ok = Broadcast.broadcast(broadcast, :status, immediate, [])
    assert_receive {:exdock_event, :activity, _revision, %{source: :status, data: ^immediate}}

    assert :ok = Broadcast.broadcast(broadcast, :status, new_delayed, delayed: true, delay_ms: 120)

    refute_receive {:exdock_event, :activity, _revision, %{source: :status, data: ^new_delayed}}, 60
    assert_receive {:exdock_event, :activity, _revision, %{source: :status, data: ^new_delayed}}, 200
  end

  test "ignores unknown broadcast types", %{broadcast: broadcast} do
    assert :ok = Broadcast.broadcast(broadcast, :unknown_type, %{value: 1}, force: true)

    refute_receive {:exdock_event, _topic, _revision, %{source: :unknown_type}}, 100
  end
end
