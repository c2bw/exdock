defmodule Exdock.Container.RuntimeStateTest do
  use ExUnit.Case, async: true

  alias Exdock.Container.RuntimeState

  @now ~U[2026-07-29 12:00:00Z]

  test "of/2 returns nil when the container has no start time" do
    assert RuntimeState.of(nil, @now) == nil
  end

  test "of/2 treats recently started containers as just started" do
    assert RuntimeState.of(DateTime.add(@now, -60, :second), @now) == :just_started
  end

  test "of/2 treats containers at the cutoff as running" do
    assert RuntimeState.of(DateTime.add(@now, -10, :minute), @now) == :running
  end
end
