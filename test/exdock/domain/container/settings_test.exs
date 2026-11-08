defmodule Exdock.Domain.Container.SettingsTest do
  use Exdock.DataCase, async: false

  alias Exdock.Server.State.Storage.Persistence.ContainerSettings, as: ContainerSettingsPersistence
  alias Exdock.Domain.Container.Settings
  alias Exdock.Container.SettingsCatalog

  test "insert/3 and load/2 round-trip runtime settings" do
    settings = %Settings{priority: 4, auto_update: :enabled, labels: ["critical"]}

    assert {:ok, _stored} = ContainerSettingsPersistence.insert(settings, "node", "app")

    assert %Settings{priority: 4, auto_update: :enabled, labels: ["critical"]} =
             ContainerSettingsPersistence.load("node", "app")
  end

  test "load/2 accepts string node keys" do
    settings = %Settings{priority: 4, auto_update: :enabled, labels: ["critical"]}

    assert {:ok, _stored} = ContainerSettingsPersistence.insert(settings, "node", "app")

    assert %Settings{priority: 4, auto_update: :enabled, labels: ["critical"]} =
             ContainerSettingsPersistence.load("node", "app")
  end

  test "load/2 returns nil for unknown container settings" do
    assert ContainerSettingsPersistence.load("node", "missing") == nil
  end

  test "import/3 applies valid fields and keeps defaults for invalid values" do
    assert {:ok, _stored} =
             ContainerSettingsPersistence.import(
               %{"priority" => 5, "auto_update" => "enabled", "labels" => ["production"]},
               "node",
               "app"
             )

    assert %Settings{priority: 5, auto_update: :enabled, labels: ["production"]} =
             ContainerSettingsPersistence.load("node", "app")

    assert {:ok, _stored} =
             ContainerSettingsPersistence.import(
               %{"priority" => 9, "auto_update" => "surprise", "labels" => [:bad]},
               "node",
               "other"
             )

    assert %Settings{priority: 3, auto_update: :passthrough, labels: []} =
             ContainerSettingsPersistence.load("node", "other")
  end

  describe "import field validation" do
    test "normalizes and validates auto-update values without dynamic atoms" do
      assert SettingsCatalog.fields() == [:priority, :auto_update, :labels]
      assert SettingsCatalog.defaults() == %{priority: 3, auto_update: :passthrough, labels: []}

      assert Settings.valid_auto_update?(:enabled)
      assert Settings.valid_auto_update?(:disabled)
      assert Settings.valid_auto_update?(:passthrough)

      refute Settings.valid_auto_update?(:invalid)
      refute Settings.valid_auto_update?("enabled")
    end

    test "documents bounded priorities and string labels" do
      assert Settings.valid_priority?(1)
      assert Settings.valid_priority?(5)
      refute Settings.valid_priority?(0)
      refute Settings.valid_priority?(6)

      assert Settings.valid_labels?(["production", "critical"])
      refute Settings.valid_labels?(["production", :critical])
    end
  end
end
