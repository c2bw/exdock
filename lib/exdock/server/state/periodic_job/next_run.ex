defmodule Exdock.Server.State.PeriodicJob.NextRun do
  @moduledoc """
  Resolves the next zoned instant for a cron expression.

  The resolver accounts for daylight-saving gaps and ambiguities while
  guaranteeing that the returned instant is strictly later than the cursor.
  Returns nil when the scheduler cannot find a future occurrence.
  """

  alias Exdock.Timezone

  @spec resolve(Crontab.CronExpression.t()) :: DateTime.t() | nil
  def resolve(%Crontab.CronExpression{} = cron_expression) do
    timezone = Timezone.user_timezone()
    resolve(cron_expression, DateTime.now!(timezone), timezone)
  end

  @spec resolve(Crontab.CronExpression.t(), DateTime.t(), String.t()) :: DateTime.t() | nil
  def resolve(
        %Crontab.CronExpression{} = cron_expression,
        %DateTime{} = now,
        timezone
      )
      when is_binary(timezone) do
    now = DateTime.shift_zone!(now, timezone)
    wall_now = DateTime.to_naive(now)
    next_run = find_next_zoned_run(cron_expression, wall_now, now, timezone)

    # Before a fall-back transition, earlier wall times can still be future
    # instants. Search that repeated interval too, then compare in UTC.
    case DateTime.from_naive(wall_now, timezone) do
      {:ambiguous, first, second} when first.utc_offset + first.std_offset == now.utc_offset + now.std_offset ->
        repeated_cursor = NaiveDateTime.add(wall_now, -DateTime.diff(second, first), :second)
        repeated_run = find_next_zoned_run(cron_expression, repeated_cursor, now, timezone)
        earliest(next_run, repeated_run)

      _unambiguous_or_second_occurrence ->
        next_run
    end
  end

  defp earliest(nil, other), do: other
  defp earliest(other, nil), do: other
  defp earliest(left, right), do: if(DateTime.compare(left, right) == :gt, do: right, else: left)

  defp find_next_zoned_run(cron_expr, naive_cursor, now, timezone) do
    cursor = strictly_after_cursor(cron_expr, naive_cursor)

    case Crontab.Scheduler.get_next_run_date(cron_expr, cursor) do
      {:ok, next_naive} -> resolve_wall_time(cron_expr, next_naive, now, timezone)
      {:error, _no_future_occurrence} -> nil
    end
  end

  defp resolve_wall_time(cron_expr, next_naive, now, timezone) do
    case DateTime.from_naive(next_naive, timezone) do
      {:ok, next_run} ->
        use_future_run_or_continue(next_run, cron_expr, next_naive, now, timezone)

      {:ambiguous, first_run, second_run} ->
        case Enum.find([first_run, second_run], &future?(&1, now)) do
          nil -> find_next_zoned_run(cron_expr, next_naive, now, timezone)
          next_run -> next_run
        end

      {:gap, _before_gap, after_gap} ->
        continue_after_gap(cron_expr, after_gap, now, timezone)

      {:error, reason} ->
        raise ArgumentError, "cannot resolve cron timezone #{inspect(timezone)}: #{inspect(reason)}"
    end
  end

  defp continue_after_gap(cron_expr, after_gap, now, timezone) do
    after_gap_naive = DateTime.to_naive(after_gap)

    if Crontab.DateChecker.matches_date?(cron_expr, after_gap_naive) and future?(after_gap, now) do
      after_gap
    else
      find_next_zoned_run(cron_expr, after_gap_naive, now, timezone)
    end
  end

  defp use_future_run_or_continue(next_run, cron_expr, next_naive, now, timezone) do
    if future?(next_run, now) do
      next_run
    else
      find_next_zoned_run(cron_expr, next_naive, now, timezone)
    end
  end

  defp strictly_after_cursor(
         %Crontab.CronExpression{extended: true},
         %NaiveDateTime{microsecond: {0, _precision}} = naive_cursor
       ) do
    NaiveDateTime.add(naive_cursor, 1, :second)
  end

  defp strictly_after_cursor(
         %Crontab.CronExpression{extended: false},
         %NaiveDateTime{second: 0, microsecond: {0, _precision}} = naive_cursor
       ) do
    NaiveDateTime.add(naive_cursor, 1, :minute)
  end

  defp strictly_after_cursor(%Crontab.CronExpression{}, %NaiveDateTime{} = naive_cursor),
    do: naive_cursor

  defp future?(candidate, now), do: DateTime.compare(candidate, now) == :gt
end
