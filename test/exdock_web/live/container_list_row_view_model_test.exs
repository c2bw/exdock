defmodule ExdockWeb.ContainerListRowViewModelTest do
  use ExUnit.Case, async: true

  alias ExdockWeb.TestFixtures.Container, as: ContainerFixture
  alias ExdockWeb.ContainersLive.ContainerListRow.ViewModel

  test "derives formatted row presentation from a running outdated container" do
    local_build = ~U[2026-01-01 00:00:00Z]
    remote_build = ~U[2026-01-04 00:00:00Z]

    container =
      ContainerFixture.read_model(
        name: "service-with-a-readable-name",
        priority: 2,
        stack_name: "platform",
        image_tag: "registry.example/service:latest",
        image_url: "https://registry.example/service",
        image_size_human: "12 MB",
        image_present_on_node: false,
        image_build_date: local_build,
        remote_image_date: remote_build,
        image_status: :outdated,
        now: ~U[2026-01-01 00:00:00Z],
        fetched_at: ~U[2026-01-01 01:00:00Z],
        configuration: %{networks: %{"host" => %{}}, ports: %{}}
      )

    row = ViewModel.build(row_input(container, true))

    assert row.pull_state == :available

    assert row.build == %{
             mode: :comparison,
             local: ~D[2026-01-01],
             remote: ~D[2026-01-04],
             age_days: 3
           }

    assert row.duration == "1h"
    assert row.lifecycle.title == "Running"
    assert row.network == :host
    assert Enum.map(row.resources, & &1.label) == ["CPU", "Memory", "I/O", "Network"]
  end

  test "derives stopped-state presentation without resource metrics" do
    container =
      ContainerFixture.read_model(
        name: "worker",
        priority: 4,
        stack_name: "jobs",
        image_tag: "worker:latest",
        image_url: "https://registry.example/worker",
        image_size_human: "8 MB",
        image_present_on_node: true,
        image_build_date: ~U[2026-01-01 00:00:00Z],
        remote_image_date: ~U[1970-01-01 00:00:00Z],
        image_status: :updated,
        is_running: false,
        now: ~U[2026-01-01 00:00:00Z],
        fetched_at: ~U[2026-01-02 00:00:00Z]
      )

    row = ViewModel.build(row_input(container, false))

    assert row.pull_state == nil
    assert row.resources == []
    assert row.lifecycle.title == "Stopped"
    assert row.network == nil
    assert row.duration == "1d"
  end

  test "advances duration from the shared render clock without a new container fetch" do
    container =
      ContainerFixture.read_model(
        name: "worker",
        is_running: true,
        now: ~U[2026-01-01 00:00:00Z],
        fetched_at: ~U[2026-01-01 00:05:00Z]
      )

    input = row_input(container, false)

    assert ViewModel.build(input).duration == "5m"

    later_input = %{input | clock_now: ~U[2026-01-01 01:05:00Z]}
    assert ViewModel.build(later_input).duration == "1h"
  end

  defp row_input(container, outdated?) do
    %{
      name: container.name,
      core: container.core,
      extended: container.extended,
      is_outdated: outdated?,
      is_running: container.core.is_running,
      clock_now: container.core.fetched_at
    }
  end
end
