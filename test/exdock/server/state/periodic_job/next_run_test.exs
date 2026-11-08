defmodule Exdock.Server.State.PeriodicJob.NextRunTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.State.PeriodicJob.NextRun

  test "skips cron occurrences in a spring-forward gap" do
    expression = parse!("30 2 * * *")
    now = DateTime.from_naive!(~N[2026-03-28 03:00:00], "Europe/Rome")

    next_run = NextRun.resolve(expression, now, "Europe/Rome")

    assert next_run == DateTime.from_naive!(~N[2026-03-30 02:30:00], "Europe/Rome")
  end

  test "uses the first matching instant after a spring-forward gap" do
    expression = parse!("* * * * *")
    now = DateTime.from_naive!(~N[2026-03-29 01:59:00], "Europe/Rome")

    assert NextRun.resolve(expression, now, "Europe/Rome") ==
             DateTime.from_naive!(~N[2026-03-29 03:00:00], "Europe/Rome")
  end

  test "uses the first future occurrence during a fall-back ambiguity" do
    expression = parse!("30 2 * * *")
    now = DateTime.from_naive!(~N[2026-10-24 03:00:00], "Europe/Rome")

    next_run = NextRun.resolve(expression, now, "Europe/Rome")

    assert {:ambiguous, first_occurrence, _second_occurrence} =
             DateTime.from_naive(~N[2026-10-25 02:30:00], "Europe/Rome")

    assert next_run == first_occurrence
  end

  test "never returns a past occurrence during the repeated fall-back hour" do
    expression = parse!("30 2 * * *")

    assert {:ambiguous, _first_now, second_now} =
             DateTime.from_naive(~N[2026-10-25 02:15:00], "Europe/Rome")

    assert {:ambiguous, _first_run, second_run} =
             DateTime.from_naive(~N[2026-10-25 02:30:00], "Europe/Rome")

    assert NextRun.resolve(expression, second_now, "Europe/Rome") == second_run
  end

  defp parse!(cron_string) do
    assert {:ok, expression} = Crontab.CronExpression.Parser.parse(cron_string)
    expression
  end

  test "includes earlier wall times that recur after the fall-back cursor" do
    assert {:ambiguous, now, _second_now} =
             DateTime.from_naive(~N[2026-10-25 02:45:00], "Europe/Rome")

    assert {:ambiguous, _first_run, second_run} =
             DateTime.from_naive(~N[2026-10-25 02:30:00], "Europe/Rome")

    assert NextRun.resolve(parse!("30 2 * * *"), now, "Europe/Rome") == second_run
  end

  test "prefers an occurrence before the clock turns back when it is sooner" do
    assert {:ambiguous, now, _second_now} =
             DateTime.from_naive(~N[2026-10-25 02:45:00], "Europe/Rome")

    assert {:ambiguous, first_run, _second_run} =
             DateTime.from_naive(~N[2026-10-25 02:46:00], "Europe/Rome")

    assert NextRun.resolve(parse!("* * * * *"), now, "Europe/Rome") == first_run
  end

  test "includes the second occurrence of the current wall time" do
    assert {:ambiguous, now, second_run} =
             DateTime.from_naive(~N[2026-10-25 02:30:00], "Europe/Rome")

    assert NextRun.resolve(parse!("30 2 * * *"), now, "Europe/Rome") == second_run
  end
end
