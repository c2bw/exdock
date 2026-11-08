defmodule Exdock.Server.State.PeriodicJobTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.State.PeriodicJob

  test "create/1 uses defaults for invalid cron strings" do
    job = PeriodicJob.create("not a cron")

    assert %PeriodicJob{cron_string: "0 22 * * *", cron_expression: %Crontab.CronExpression{}} = job
    assert DateTime.compare(job.next_run, DateTime.utc_now()) == :gt
  end

  test "replace/2 updates valid cron and keeps the previous job for invalid cron" do
    initial = PeriodicJob.create("0 22 * * *")

    assert {:ok, replaced} = PeriodicJob.replace(initial, "0 8 * * *")

    assert %PeriodicJob{cron_string: "0 8 * * *"} = replaced

    assert {:error, ^replaced} = PeriodicJob.replace(replaced, "invalid cron")
  end

  test "valid?/1 validates cron expressions" do
    assert PeriodicJob.valid?("0 22 * * *")
    refute PeriodicJob.valid?("bad cron")
  end

  test "next_run/1 computes a future tick for valid expressions" do
    assert %DateTime{} = next = PeriodicJob.next_run("0 22 * * *")
    assert DateTime.to_unix(next) > DateTime.to_unix(DateTime.utc_now())
  end

  test "next_run/1 returns nil for invalid cron strings" do
    assert is_nil(PeriodicJob.next_run("not a cron"))
  end

  test "rejects parsed schedules without a future occurrence and restores safely" do
    cron = "0 0 31 2 *"
    initial = PeriodicJob.create("0 8 * * *")

    refute PeriodicJob.valid?(cron)
    assert PeriodicJob.next_run(cron) == nil
    assert {:error, ^initial} = PeriodicJob.replace(initial, cron)
    assert %PeriodicJob{cron_string: ^cron, next_run: nil} = PeriodicJob.create(cron)
  end

  test "exhausted finite schedules stay inactive across rollover and restoration" do
    cron = "0 0 1 1 * 2025"
    assert %DateTime{year: 2025} = PeriodicJob.next_run(cron, ~U[2024-12-31 00:00:00Z], "Etc/UTC")

    exhausted = %PeriodicJob{
      cron_string: cron,
      cron_expression: Crontab.CronExpression.Parser.parse!(cron),
      next_run: ~U[2025-01-01 00:00:00Z]
    }

    assert %PeriodicJob{cron_string: ^cron, next_run: nil} = PeriodicJob.set_next(exhausted)
    assert %PeriodicJob{cron_string: ^cron, next_run: nil} = PeriodicJob.create(cron)
    assert {:ok, %PeriodicJob{next_run: %DateTime{}}} = PeriodicJob.replace(PeriodicJob.create(cron), "0 8 * * *")
  end
end
