defmodule Exdock.Domain.UserSettingsTest do
  use Exdock.DataCase, async: false

  alias Exdock.Server.State.Storage.Persistence.UserSettings, as: UserSettingsPersistence
  alias Exdock.Domain.UserSettings

  test "load/1 returns defaults until settings are persisted" do
    assert %UserSettings{user: "admin", automation_enabled: false} =
             UserSettingsPersistence.load("admin")
  end

  test "insert/1 and load/1 round-trip runtime settings" do
    settings =
      UserSettings.default()
      |> UserSettings.set(:automation_enabled, true)
      |> UserSettings.set(:auto_update_above, 4)
      |> UserSettings.set(:cron_string, "0 8 * * *")

    assert {:ok, _stored} = UserSettingsPersistence.insert(settings)

    assert %UserSettings{
             user: "admin",
             automation_enabled: true,
             auto_update_above: 4,
             cron_string: "0 8 * * *"
           } = UserSettingsPersistence.load("admin")
  end

  describe "set/3" do
    test "coerces boolean strings from LiveView params" do
      settings = UserSettings.default()

      assert %UserSettings{rendering_statistics: true} = UserSettings.set(settings, :rendering_statistics, "true")
      assert %UserSettings{rendering_statistics: false} = UserSettings.set(settings, :rendering_statistics, "false")
    end

    test "coerces numeric strings from LiveView params" do
      assert %UserSettings{auto_update_above: 4} = UserSettings.set(UserSettings.default(), :auto_update_above, "4")
      assert %UserSettings{auto_update_above: 0} = UserSettings.set(UserSettings.default(), :auto_update_above, "0")
    end

    test "ignores invalid LiveView params" do
      settings = %UserSettings{UserSettings.default() | cron_string: "0 22 * * *", auto_update_above: 3}

      assert ^settings = UserSettings.set(settings, :rendering_statistics, "sometimes")
      assert ^settings = UserSettings.set(settings, :auto_update_above, "9")
      assert ^settings = UserSettings.set(settings, :cron_string, "not a cron")
    end

    test "accepts only valid cron strings" do
      assert %UserSettings{cron_string: "0 8 * * *"} = UserSettings.set(UserSettings.default(), :cron_string, "0 8 * * *")
    end
  end

  describe "validate_setting/2" do
    test "canonicalizes supported external values" do
      assert {:ok, {:rendering_statistics, true}} =
               UserSettings.validate_setting("rendering_statistics", "true")

      assert {:ok, {:auto_update_above, 4}} =
               UserSettings.validate_setting(:auto_update_above, "4")

      assert {:ok, {:auto_update_above, 0}} =
               UserSettings.validate_setting(:auto_update_above, "0")
    end

    test "returns structured errors for unsupported inputs" do
      assert {:error, {:unknown_user_setting, :unknown}} =
               UserSettings.validate_setting(:unknown, true)

      assert {:error, {:invalid_user_setting_value, :automation_enabled}} =
               UserSettings.validate_setting(:automation_enabled, "sometimes")
    end
  end

  describe "import field validation" do
    test "documents valid import predicates" do
      assert UserSettings.valid_update_threshold?(0)
      assert UserSettings.valid_update_threshold?(4)
      refute UserSettings.valid_update_threshold?(-1)
      refute UserSettings.valid_update_threshold?(5)

      assert UserSettings.valid_cron?("0 22 * * *")
      refute UserSettings.valid_cron?("not a cron")
    end
  end
end
