defmodule ExdockWeb.Presentation.ContainerTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.Presentation.Container

  test "maps every supported priority to its shared presentation class" do
    assert Enum.map(1..5, &Container.priority_class/1) == [
             "bg-priority-one",
             "bg-priority-two",
             "bg-priority-three",
             "bg-priority-four",
             "bg-priority-five"
           ]
  end

  test "formats container labels with their view-specific limits" do
    assert Container.container_name("short-name") == "short-name"
    assert Container.container_name(String.duplicate("a", 29)) == "aaaaaaaaaaaaaa..aaaaaaaaaaaaaa"
    assert Container.stack_name(String.duplicate("b", 17)) == "bbbbbbbb..bbbbbbbb"
    assert Container.image_tag(String.duplicate("c", 29)) == "cccccccccccccc..cccccccccccccc"
  end

  test "formats running time and the unset timestamp" do
    fetched_at = ~U[2026-07-30 12:00:10Z]

    assert Container.running_time(~U[0001-01-01 00:00:00Z], fetched_at) == "-"
    assert Container.running_time(~U[2026-07-30 12:00:00Z], fetched_at) == "10s"
  end

  test "formats build dates and calculates complete age days" do
    local_build = ~U[2026-07-27 18:00:00.123456Z]
    remote_build = ~U[2026-07-30 17:59:59Z]

    assert Container.build_date_iso8601(local_build) == "2026-07-27T18:00:00Z"
    assert Container.build_age_days(local_build, remote_build) == 2
    assert Container.remote_build_available?(remote_build)
    refute Container.remote_build_available?(~U[1970-01-01 00:00:00Z])
  end
end
