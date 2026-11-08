defmodule Exdock.Settings.UserFieldCatalogTest do
  use ExUnit.Case, async: true

  alias Exdock.Database
  alias Exdock.Settings.UserFieldCatalog
  alias Exdock.Domain.UserSettings

  test "runtime and database settings expose every catalog field" do
    catalog_fields = MapSet.new(UserFieldCatalog.keys())
    runtime_fields = %UserSettings{} |> Map.from_struct() |> Map.delete(:user) |> Map.keys() |> MapSet.new()
    database_fields = Database.UserSettings.__schema__(:fields) |> List.delete(:user) |> MapSet.new()

    assert runtime_fields == catalog_fields
    assert database_fields == catalog_fields
  end

  test "resolves only declared atom and external keys" do
    assert UserFieldCatalog.resolve(:rendering_statistics) == {:ok, :rendering_statistics}
    assert UserFieldCatalog.resolve("rendering_statistics") == {:ok, :rendering_statistics}
    assert UserFieldCatalog.resolve("unknown") == :error
    assert UserFieldCatalog.resolve(:unknown) == :error
    assert UserFieldCatalog.external(:rendering_statistics) == "rendering_statistics"
  end

  test "owns defaults used by runtime settings" do
    defaults = Map.new(UserFieldCatalog.defaults())
    settings = UserSettings.default() |> Map.from_struct() |> Map.delete(:user)

    assert settings == defaults
    assert UserSettings.default_user() == UserFieldCatalog.default_user()
  end
end
