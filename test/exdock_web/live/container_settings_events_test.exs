defmodule ExdockWeb.ContainerSettingsEventsTest do
  use ExdockWeb.LiveCase

  alias ExdockWeb.PageLive.Utils.ContainerSettingsEvents

  test "submits validated priority changes" do
    params = %{"node" => "node_a", "container" => "api", "priority" => "4"}

    assert {:operation, {:ok, operation_id}} =
             ContainerSettingsEvents.change_priority(params)

    assert {:ok, _uuid} = Ecto.UUID.cast(operation_id)
  end

  test "rejects invalid and malformed priority changes before submission" do
    assert {:invalid, :invalid_priority} =
             ContainerSettingsEvents.change_priority(%{
               "node" => "node_a",
               "container" => "api",
               "priority" => "6"
             })

    assert {:invalid, :invalid_priority} =
             ContainerSettingsEvents.change_priority(%{
               "node" => " ",
               "container" => "api",
               "priority" => "3"
             })

    assert {:invalid, :invalid_request} =
             ContainerSettingsEvents.change_priority(%{"priority" => "3"})
  end

  test "normalizes and transitions auto-update policies in both directions" do
    assert {:ok, :enabled} =
             ContainerSettingsEvents.next_auto_update_policy("passthrough", "next")

    assert {:ok, :disabled} =
             ContainerSettingsEvents.next_auto_update_policy(:passthrough, "prev")

    assert {:ok, :passthrough} =
             ContainerSettingsEvents.next_auto_update_policy("enabled", "prev")

    assert {:ok, :passthrough} =
             ContainerSettingsEvents.next_auto_update_policy(:disabled, "next")
  end

  test "treats policy endpoints as no-ops and rejects invalid transitions" do
    assert :noop = ContainerSettingsEvents.next_auto_update_policy(:enabled, "next")
    assert :noop = ContainerSettingsEvents.next_auto_update_policy("disabled", "prev")

    assert {:error, :invalid_auto_update} =
             ContainerSettingsEvents.next_auto_update_policy("unknown", "next")

    assert {:error, :invalid_auto_update} =
             ContainerSettingsEvents.next_auto_update_policy(:enabled, "sideways")
  end

  test "submits auto-update changes from the canonical event shape" do
    params = %{
      "node" => "node_a",
      "container" => "api",
      "current-policy" => "passthrough",
      "next" => "next"
    }

    assert {:operation, {:ok, operation_id}} =
             ContainerSettingsEvents.change_auto_update(params)

    assert {:ok, _uuid} = Ecto.UUID.cast(operation_id)
  end

  test "validates auto-update event parameters before submission" do
    assert :noop =
             ContainerSettingsEvents.change_auto_update(%{
               "node" => "node_a",
               "container" => "api",
               "current-policy" => "enabled",
               "next" => "next"
             })

    assert {:invalid, :invalid_auto_update} =
             ContainerSettingsEvents.change_auto_update(%{
               "node" => "node_a",
               "container" => "",
               "current-policy" => "enabled",
               "next" => "prev"
             })

    assert {:invalid, :invalid_request} =
             ContainerSettingsEvents.change_auto_update(%{"next" => "prev"})
  end
end
