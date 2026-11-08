defmodule Exdock.ScheduleTest do
  use ExUnit.Case, async: true

  alias Exdock.Schedule

  test "calculates the next run from an explicit clock" do
    now = ~U[2026-01-01 20:00:00Z]

    assert Schedule.next_run("0 22 * * *", now, "Etc/UTC") == ~U[2026-01-01 22:00:00Z]
  end

  test "normalizes an explicit UTC clock into the schedule timezone" do
    now = ~U[2026-01-01 20:00:00Z]

    assert Schedule.next_run("0 22 * * *", now, "Europe/Rome") ==
             DateTime.from_naive!(~N[2026-01-01 22:00:00], "Europe/Rome")
  end

  test "returns nil for an invalid schedule" do
    assert Schedule.next_run("invalid", ~U[2026-01-01 20:00:00Z], "Etc/UTC") == nil
  end
end
