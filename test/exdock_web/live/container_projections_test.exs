defmodule ExdockWeb.ContainerProjectionsTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.ContainersLive.ContainerGroups
  alias ExdockWeb.HomepageLive.MassContainerManager.PriorityGroup
  alias ExdockWeb.TestFixtures.Container, as: ContainerFixture

  test "container groups partition once and order by priority then name" do
    fixtures = [
      fixture("zeta", :updated, true, 2),
      fixture("alpha", :updated, true, 5),
      fixture("outdated", :outdated, true, 3),
      fixture("unknown", :unknown, true, 3),
      fixture("stopped", :updated, false, 4)
    ]

    groups =
      ContainerGroups.build(
        Map.new(fixtures, fn {key, core} -> {key, core} end),
        %{}
      )

    assert names(groups.ok) == ["alpha", "zeta"]
    assert names(groups.outdated) == ["outdated"]
    assert names(groups.unknown) == ["unknown"]
    assert names(groups.stopped) == ["stopped"]
  end

  test "priority projection deduplicates pull work and image size together" do
    first = fixture("api", :outdated, true, 4, image_tag: "repo/api", image_size: 10)
    duplicate = fixture("worker", :outdated, true, 4, image_tag: "repo/api:latest", image_size: 10)
    distinct = fixture("jobs", :outdated, true, 4, image_tag: "repo/jobs:latest", image_size: 20)

    containers =
      Enum.map([first, duplicate, distinct], fn {key, core} -> {"node-a", key, core} end)

    group = PriorityGroup.build({4, containers})

    assert group.image_size == 30

    assert group.pull_jobs == [
             %{node: "node-a", image_tag: "repo/api"},
             %{node: "node-a", image_tag: "repo/jobs:latest"}
           ]

    assert Enum.map(group.recreate_jobs, & &1.name) == ["api", "worker", "jobs"]
  end

  defp fixture(name, status, running?, priority, extra \\ []) do
    container =
      ContainerFixture.read_model([name: name, image_status: status, is_running: running?, priority: priority] ++ extra)

    {%{name: name, id: container.id}, container.core}
  end

  defp names(rows), do: Enum.map(rows, fn {key, _core, _extended} -> key.name end)
end
