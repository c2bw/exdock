defmodule Exdock.Server.AutomationSchedulerTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.AutomationScheduler
  alias Exdock.Server.State.PeriodicJob

  test "ignores timer messages from an older generation" do
    job = PeriodicJob.create("0 22 * * *")
    state = %AutomationScheduler{generation: 2, job: job}

    assert {:noreply, ^state} = AutomationScheduler.handle_info({:automation_tick, 1}, state)
  end

  test "replaces an active schedule and advances its generation" do
    old_job = PeriodicJob.create("0 22 * * *")
    new_job = PeriodicJob.create("0 23 * * *")
    old_timer = Process.send_after(self(), :old_tick, 60_000)
    state = %AutomationScheduler{generation: 2, job: old_job, timer: old_timer}

    assert {:noreply, updated} = AutomationScheduler.handle_cast({:replace, new_job}, state)
    assert updated.generation == 3
    assert updated.job == new_job
    assert is_reference(updated.timer)

    Process.cancel_timer(updated.timer)
  end

  test "exhausted schedules cancel timers and ignore ticks without running automation" do
    exhausted = PeriodicJob.create("0 0 1 1 * 2025")
    old_timer = Process.send_after(self(), :old_tick, 60_000)
    state = %AutomationScheduler{generation: 2, job: PeriodicJob.create("0 22 * * *"), timer: old_timer}
    assert {:noreply, updated} = AutomationScheduler.handle_cast({:replace, exhausted}, state)
    assert updated.job.cron_string == exhausted.cron_string
    assert updated.timer == nil
    assert Process.read_timer(old_timer) == false
    assert {:noreply, ^updated} = AutomationScheduler.handle_info({:automation_tick, updated.generation}, updated)
    assert {:noreply, ^updated} = AutomationScheduler.handle_info({:automation_tick, state.generation}, updated)
  end

  test "replace is a no-op when the scheduler is not running" do
    unless Process.whereis(AutomationScheduler) do
      assert AutomationScheduler.replace(PeriodicJob.create("0 22 * * *")) == :ok
    end
  end
end
