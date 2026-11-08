defmodule Exdock.Server.Broadcast.PolicyTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Broadcast.{BroadcastState, Policy}

  test "an open window flushes an immediate payload and enters cooldown" do
    payload = {%{value: 1}, 4}

    assert {state,
            [
              {:schedule, {:cooldown}, 100},
              {:publish, %{status: ^payload}}
            ]} = Policy.stage(BroadcastState.new(), :status, payload, [])

    refute state.broadcast_window_open
    refute state.immediate_flush_needed
    assert state.staged_immediate_buckets == %{}
  end

  test "closed windows queue only the latest immediate payload" do
    state = BroadcastState.new() |> BroadcastState.close_broadcast_window()
    first = {%{value: 1}, nil}
    latest = {%{value: 2}, nil}

    assert {state, []} = Policy.stage(state, :status, first, [])
    assert {state, []} = Policy.stage(state, :status, latest, [])
    assert state.staged_immediate_buckets == %{status: latest}
  end

  test "delayed staging schedules once and keeps only the latest payload" do
    first = {%{value: 1}, nil}
    latest = {%{value: 2}, 9}

    assert {state, [{:schedule, {:broadcast_delayed, :status, generation}, 25}]} =
             Policy.stage(BroadcastState.new(), :status, first, delayed: true, delay_ms: 25)

    assert {state, []} = Policy.stage(state, :status, latest, delayed: true, delay_ms: 25)
    assert state.staged_delayed_buckets == %{status: latest}
    assert state.delayed_generations == %{status: generation}
  end

  test "an immediate payload supersedes delayed data for the same type" do
    delayed = {%{value: 1}, nil}
    immediate = {%{value: 2}, nil}

    {state, _effects} = Policy.stage(BroadcastState.new(), :status, delayed, delayed: true)

    assert {state, [{:schedule, {:cooldown}, 100}, {:publish, %{status: ^immediate}}]} =
             Policy.stage(state, :status, immediate, [])

    assert state.staged_delayed_buckets == %{}
  end

  test "a delayed timer releases its latest payload through the immediate policy" do
    payload = {%{value: 2}, 7}

    {state, [{:schedule, {:broadcast_delayed, :status, generation}, 25}]} =
      Policy.stage(BroadcastState.new(), :status, payload, delayed: true, delay_ms: 25)

    assert {state, [{:schedule, {:cooldown}, 100}, {:publish, %{status: ^payload}}]} =
             Policy.delayed_ready(state, :status, generation)

    assert state.staged_delayed_buckets == %{}
    assert state.staged_immediate_buckets == %{}
  end

  test "a stale timer cannot release a payload from a newer delayed window" do
    old_delayed = {%{value: 1}, nil}
    immediate = {%{value: 2}, nil}
    new_delayed = {%{value: 3}, nil}

    {state, [{:schedule, {:broadcast_delayed, :status, old_generation}, _delay_ms}]} =
      Policy.stage(BroadcastState.new(), :status, old_delayed, delayed: true)

    {state, _effects} = Policy.stage(state, :status, immediate, [])

    {state, [{:schedule, {:broadcast_delayed, :status, new_generation}, _delay_ms}]} =
      Policy.stage(state, :status, new_delayed, delayed: true)

    assert new_generation > old_generation
    assert {unchanged_state, []} = Policy.delayed_ready(state, :status, old_generation)
    assert unchanged_state == state
    assert unchanged_state.staged_delayed_buckets == %{status: new_delayed}

    assert {released_state, [{:schedule, {:cooldown}, 100}, {:publish, %{status: ^new_delayed}}]} =
             Policy.delayed_ready(unchanged_state, :status, new_generation)

    assert released_state.staged_delayed_buckets == %{}
  end

  test "cooldown flushes queued payloads before scheduling the window reopen" do
    payload = {%{value: 1}, nil}
    state = BroadcastState.new() |> BroadcastState.close_broadcast_window()
    {state, []} = Policy.stage(state, :status, payload, [])

    assert {state,
            [
              {:schedule, {:ready_to_broadcast}, 100},
              {:publish, %{status: ^payload}}
            ]} = Policy.cooldown(state)

    refute state.broadcast_window_open
    refute state.immediate_flush_needed
    assert {opened, []} = Policy.ready(state)
    assert opened.broadcast_window_open
  end

  test "reopening the window publishes job completion buffered after cooldown without another update" do
    working = {%{jobs: %{refresh: :running}}, 1}
    ready = {%{jobs: %{}}, 3}
    logs = {[%{status: :finished}], 3}

    {state, _effects} = Policy.stage(BroadcastState.new(), :status, working, [])
    {state, [{:schedule, {:ready_to_broadcast}, 100}]} = Policy.cooldown(state)

    # The job finishes after cooldown flushes, while the window is still closed.
    {state, []} = Policy.stage(state, :status, {%{jobs: %{refresh: :finishing}}, 2}, [])
    {state, []} = Policy.stage(state, :status, ready, [])
    {state, []} = Policy.stage(state, :log, logs, [])

    assert {state, [{:schedule, {:cooldown}, 100}, {:publish, %{status: ^ready, log: ^logs}}]} = Policy.ready(state)
    assert state.staged_immediate_buckets == %{}
    refute state.immediate_flush_needed
    refute state.broadcast_window_open

    # Once idle, the timer chain ends with an open window and no empty broadcasts.
    assert {state, [{:schedule, {:ready_to_broadcast}, 100}]} = Policy.cooldown(state)
    assert {state, []} = Policy.ready(state)
    assert state.broadcast_window_open
  end
end
