defmodule Exdock.Runtime.ProjectionTest do
  use ExUnit.Case, async: true

  alias Exdock.Runtime.Projection
  alias Exdock.ReadModel.Container
  alias Exdock.ReadModel.Container.Key
  alias Exdock.Domain.Container, as: StorageContainer

  test "container projections default missing telemetry" do
    container = %StorageContainer{node: "c3", name: "api", id: "api-id", core: core_fixture()}

    assert %{logs: nil, resources: %{records: []}} =
             container |> List.wrap() |> Projection.container_list_extended() |> Map.fetch!(%Key{name: "api", id: "api-id"})
  end

  test "container projections normalize explicit nil telemetry resources" do
    container = %StorageContainer{
      node: "c3",
      name: "api",
      id: "api-id",
      core: core_fixture(),
      extended: %{resources: nil}
    }

    assert %{resources: %{rates: %{cpu_usage: nil}, records: []}} =
             container |> Container.from_domain() |> Map.fetch!(:extended)
  end

  test "container detail projections accept storage containers from broadcasts" do
    storage_container = %StorageContainer{
      node: "c3",
      name: "scrutinyweb",
      id: "container-id",
      core: %{
        is_running: true,
        stack_name: "scrutiny",
        configuration: %{networks: %{}, ports: %{}},
        state: %{started_at: ~U[2026-01-01 00:00:00Z], finished_at: nil, restarting: false},
        json_compressed_inspect: :zlib.gzip("{}"),
        settings: %{priority: 3, auto_update: :passthrough, labels: []},
        is_deleted: false,
        fetched_at: ~U[2026-01-01 01:00:00Z],
        image_data: %{
          image: %{
            registry_url: "ghcr.io/analogj/scrutiny",
            size: 123,
            size_human: "123 B",
            build_date: ~U[2025-12-01 00:00:00Z],
            metadata: %{repository_url: "https://github.com/AnalogJ/scrutiny"}
          },
          tag_info: %{tag: "master-web", latest_date: ~U[2026-01-01 00:00:00Z]},
          present_on_node: true,
          status: :updated
        }
      },
      extended: %{logs: %{lines: []}, resources: %{records: []}}
    }

    key = %Key{name: "scrutinyweb", id: "container-id"}
    core = storage_container |> List.wrap() |> Projection.containers_core() |> Map.fetch!(key)
    extended = storage_container |> List.wrap() |> Projection.container_list_extended() |> Map.fetch!(key)
    node_extended = Projection.containers_extended(%{"c3" => [storage_container]})

    assert core.settings.priority == 3
    assert core.image_status == :updated
    assert core.image_tag == "master-web"
    assert extended.logs.lines == []
    assert node_extended["c3"][key].logs.lines == []
  end

  defp core_fixture do
    %{
      is_running: true,
      stack_name: "api",
      configuration: %{networks: %{}, ports: %{}},
      state: %{started_at: ~U[2026-01-01 00:00:00Z], finished_at: nil, restarting: false},
      json_compressed_inspect: :zlib.gzip("{}"),
      settings: %{priority: 1, auto_update: :passthrough, labels: []},
      is_deleted: false,
      fetched_at: ~U[2026-01-01 01:00:00Z],
      image_data: %{
        image: %{
          registry_url: "example/api",
          size: 123,
          size_human: "123 B",
          build_date: ~U[2025-12-01 00:00:00Z],
          metadata: %{}
        },
        tag_info: %{tag: "latest", latest_date: ~U[2026-01-01 00:00:00Z]},
        present_on_node: false,
        status: :unknown
      }
    }
  end
end
