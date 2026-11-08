defmodule ExdockWeb.RenderStatisticsTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.PageLive.Utils.RenderStatistics

  test "enabling is idempotent and disabling cancels the owned timer" do
    timer = RenderStatistics.set(nil, true)

    assert RenderStatistics.set(timer, true) == timer
    assert is_integer(Process.read_timer(timer.ref))
    assert RenderStatistics.set(timer, false) == nil
    assert Process.read_timer(timer.ref) == false
  end

  test "only the current timer message can schedule the next sample" do
    timer = RenderStatistics.set(nil, true)
    stale_token = make_ref()

    assert RenderStatistics.advance(timer, stale_token) == :stale
    assert {:ok, next_timer} = RenderStatistics.advance(timer, timer.token)
    assert next_timer.token != timer.token

    RenderStatistics.set(timer, false)
    RenderStatistics.set(next_timer, false)
  end

  test "a delivered message stays stale after statistics are disabled" do
    timer = RenderStatistics.set(nil, true)
    assert RenderStatistics.set(timer, false) == nil
    assert RenderStatistics.advance(nil, timer.token) == :stale
  end
end
