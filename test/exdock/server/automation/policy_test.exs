defmodule Exdock.Server.Automation.PolicyTest do
  use ExUnit.Case, async: true

  alias Exdock.Domain.UserSettings
  alias Exdock.Server.Automation.Policy
  alias Exdock.Server.State
  alias Exdock.Server.State.PeriodicJob
  alias Exdock.Server.State.Storage.Settings

  test "enabled automation describes refresh, release, and completion effects" do
    state = state_with_settings(automation_enabled: true, auto_update_containers: true, auto_update_releases: true)

    assert {%State{revision: 1}, effects} = Policy.run(state, "operation-id")
    assert [{:command, nil, _container_refresh, []}, {:command, nil, _release_refresh, [automated: true]} | _] = effects

    assert List.last(effects) ==
             {:operation_finished, "operation-id", :run_automation, %{status: :completed}}
  end

  test "disabled automation only completes an admitted operation" do
    state = state_with_settings(automation_enabled: false)

    assert {%State{revision: 1}, [{:operation_finished, "operation-id", :run_automation, %{status: :completed}}]} =
             Policy.run(state, "operation-id")
  end

  test "schedule decisions preserve invalid schedules and expose valid persistence mutations" do
    state = state_with_settings([])

    assert {:reject, ^state} = Policy.change_schedule(state, "invalid cron")

    assert {:commit, %State{periodic_job: %PeriodicJob{cron_string: "0 8 * * *"}}, mutation} =
             Policy.change_schedule(state, "0 8 * * *")

    assert mutation.domain == :settings
    assert mutation.action == :user_setting
  end

  defp state_with_settings(overrides) do
    user = UserSettings.default_user()
    settings = struct!(UserSettings.default(), overrides)

    %State{
      revision: 0,
      settings: %Settings{user: %{user => settings}},
      periodic_job: PeriodicJob.create("0 22 * * *")
    }
  end
end
