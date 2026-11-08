defmodule Exdock.ClientLib.Async.BatchTest do
  use ExUnit.Case, async: true

  alias Exdock.ClientLib.Async.Batch

  test "records the explicit time used for an immediate run" do
    now = ~U[2026-07-31 12:00:00Z]
    batch = Batch.new(:resources, "batch-1", 2, 1_000, fn -> :ok end)

    assert {%Batch{count: 1, last_run: ^now}, true, 1_000} = Batch.run(batch, now)
  end

  test "uses one explicit time to calculate the remaining delay" do
    last_run = ~U[2026-07-31 12:00:00Z]
    now = DateTime.add(last_run, 250, :millisecond)

    batch = %Batch{
      name: :resources,
      id: "batch-1",
      count: 1,
      interval: 1_000,
      function: fn -> :ok end,
      last_run: last_run
    }

    assert {^batch, false, 750} = Batch.run(batch, now)
  end
end
