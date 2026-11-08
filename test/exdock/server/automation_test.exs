defmodule Exdock.Server.AutomationTest do
  use ExUnit.Case, async: true

  alias Exdock.Domain.UserSettings
  alias Exdock.Server.Automation
  alias Exdock.Server.State
  alias Exdock.Server.State.PeriodicJob
  alias Exdock.Server.State.Storage.Settings

  test "delegates planned effects to an injected handler" do
    user = UserSettings.default_user()

    state = %State{
      revision: 0,
      settings: %Settings{user: %{user => UserSettings.default()}},
      periodic_job: PeriodicJob.create("0 22 * * *")
    }

    assert %State{revision: 1} = Automation.run(state, "operation-id", __MODULE__)
    assert_received {:automation_effects, effects}
    assert {:operation_finished, "operation-id", :run_automation, %{status: :completed}} in effects
  end

  def run(effects) do
    send(self(), {:automation_effects, effects})
    :ok
  end
end
