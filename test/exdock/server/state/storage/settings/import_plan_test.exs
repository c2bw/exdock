defmodule Exdock.Server.State.Storage.Settings.ImportPlanTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.State.Storage.Settings.Importer.Plan

  test "builds all valid sections before persistence" do
    plan =
      Plan.build(
        %{
          user_settings: %{"automation_enabled" => true},
          nodes_settings: %{"node-a" => %{"web_ui" => "https://node.example"}},
          containers_settings: %{"node-a" => %{"api" => %{"priority" => 5}}},
          images_settings: %{"node-a" => %{"sha256:image" => %{"delete_lock" => true}}},
          repository_overrides: %{"repo/api:latest" => %{"repository_url" => "https://example.com/api"}}
        },
        MapSet.new(["node-a"])
      )

    assert plan.warnings == []
    assert Keyword.fetch!(plan.sections, :nodes_settings) == [{"node-a", %{"web_ui" => "https://node.example"}}]

    assert Keyword.fetch!(plan.sections, :containers_settings) == [
             {"node-a", "api", %{"priority" => 5}}
           ]
  end

  test "records skipped sections and unknown nodes without planning their entries" do
    plan =
      Plan.build(
        %{
          user_settings: nil,
          nodes_settings: %{"missing-node" => %{"web_ui" => "https://missing.example"}},
          containers_settings: "invalid",
          images_settings: %{},
          repository_overrides: %{}
        },
        MapSet.new()
      )

    assert {:unknown_node, "missing-node"} in plan.warnings
    assert {:invalid_section, "containers settings"} in plan.warnings
    assert Keyword.fetch!(plan.sections, :nodes_settings) == []
    refute Keyword.has_key?(plan.sections, :containers_settings)
  end
end
