defmodule ExdockWeb.SettingsCatalogTest do
  use ExUnit.Case, async: true

  alias Exdock.Container.Policy
  alias Exdock.Settings.UserFieldCatalog
  alias ExdockWeb.SettingsCatalog

  test "web controls use canonical external setting names" do
    controls = SettingsCatalog.toggles(:preferences) ++ SettingsCatalog.toggles(:automation)

    for control <- controls do
      assert control.external == UserFieldCatalog.external(control.key)
      assert UserFieldCatalog.kind(control.key) == :boolean
    end
  end

  test "automation threshold uses the dedicated policy bounds" do
    threshold = SettingsCatalog.automation_threshold()

    assert threshold.external == UserFieldCatalog.external(:auto_update_above)
    assert threshold.min == Policy.min_update_threshold()
    assert threshold.max == Policy.max_update_threshold()
  end
end
