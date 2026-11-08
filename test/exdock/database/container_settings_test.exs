defmodule Exdock.Database.ContainerSettingsTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database.ContainerSettings
  alias Exdock.Domain.Container.Settings

  test "round-trips string-backed settings" do
    settings = %Settings{priority: 4, auto_update: :enabled, labels: ["critical"]}

    assert {:ok, %ContainerSettings{node: "node", name: "app", auto_update: :enabled}} =
             settings
             |> persisted_settings("node", "app")
             |> ContainerSettings.insert()

    assert %ContainerSettings{
             node: "node",
             name: "app",
             priority: 4,
             auto_update: :enabled,
             labels: ["critical"]
           } = ContainerSettings.load("node", "app")
  end

  test "load/2 accepts validated string node keys" do
    settings = %Settings{priority: 4, auto_update: :enabled, labels: ["critical"]}

    assert {:ok, %ContainerSettings{}} =
             settings
             |> persisted_settings("node", "app")
             |> ContainerSettings.insert()

    assert %ContainerSettings{
             node: "node",
             name: "app",
             priority: 4,
             auto_update: :enabled,
             labels: ["critical"]
           } = ContainerSettings.load("node", "app")
  end

  test "load_all rehydrates stored node and auto-update values" do
    enabled = %Settings{priority: 2, auto_update: :enabled, labels: ["public"]}
    passthrough = %Settings{priority: 3, auto_update: :passthrough, labels: []}

    assert {:ok, %ContainerSettings{}} =
             enabled
             |> persisted_settings("node_a", "web")
             |> ContainerSettings.insert()

    assert {:ok, %ContainerSettings{}} =
             passthrough
             |> persisted_settings("node_b", "worker")
             |> ContainerSettings.insert()

    assert [
             %ContainerSettings{node: "node_a", name: "web", auto_update: :enabled},
             %ContainerSettings{node: "node_b", name: "worker", auto_update: :passthrough}
           ] = ContainerSettings.load_all() |> Enum.sort_by(& &1.name)
  end

  test "insert upserts settings for the same container identity" do
    original = %Settings{priority: 1, auto_update: :disabled, labels: []}
    updated = %Settings{priority: 5, auto_update: :enabled, labels: ["critical"]}

    assert {:ok, %ContainerSettings{}} =
             original
             |> persisted_settings("node", "api")
             |> ContainerSettings.insert()

    assert {:ok, %ContainerSettings{}} =
             updated
             |> persisted_settings("node", "api")
             |> ContainerSettings.insert()

    assert %ContainerSettings{
             node: "node",
             name: "api",
             priority: 5,
             auto_update: :enabled,
             labels: ["critical"]
           } = ContainerSettings.load("node", "api")
  end

  defp persisted_settings(%Settings{} = settings, node, name) do
    settings
    |> Map.from_struct()
    |> Map.merge(%{node: node, name: name})
    |> ContainerSettings.new()
  end
end
