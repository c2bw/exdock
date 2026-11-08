defmodule ExdockWeb.Commons.NodeSummary.ViewModelTest do
  use ExUnit.Case, async: true

  alias Exdock.Domain.Container.Resources
  alias Exdock.Domain.Container.Resources.Rates
  alias ExdockWeb.Commons.NodeSummary.{ResourceSummary, ViewModel}

  test "builds presentation-ready container metrics, resources, status, and actions" do
    model = ViewModel.new(container_assigns())

    assert model.summary_type == :containers
    assert model.nodename == "node-a"
    assert model.platform == "linux/amd64"
    assert Enum.map(model.metrics, & &1.value) == [2, 3, 4]

    assert model.resource_rows
           |> List.flatten()
           |> Enum.map(& &1.value) == ["12.5%", "1.5 KB/s", "1.5 KB", "3.0 KB/s"]

    assert model.resource_rows
           |> List.flatten()
           |> Enum.map(& &1.detail) ==
             ["4 CPUs available", "3.0 KB total", "8.0 KB available", "7.0 KB total"]

    assert Enum.map(model.status.items, & &1.count) == [1, 0, 1, 1]
    assert model.state_icons.restarting == %{icon: "hero-cog", color: "text-eye-secondary"}
    assert model.state_icons.recently_started == %{icon: "hero-cog", color: "text-warning"}
    assert model.staleness == %{icon: "hero-clock", color: "text-success", text: "2 seconds ago"}
    assert model.actions == %{nodename: "node-a", web_ui: "https://node-a.test", registry_fetch?: true}
  end

  test "builds the smaller image summary variant without container-only data" do
    assigns =
      container_assigns()
      |> Map.put(:summary_type, :images)

    model = ViewModel.new(assigns)

    assert Enum.map(model.metrics, & &1.icon) == ["hero-square-2-stack", "hero-circle-stack"]
    assert model.resource_rows == []
    assert Enum.map(model.status.items, & &1.count) == [1, 2, 1]
    assert model.state_icons == %{restarting: nil, recently_started: nil}
    refute model.actions.registry_fetch?
  end

  test "derives recently-started presentation from the current page clock" do
    model =
      container_assigns()
      |> Map.put(:clock_now, ~U[2026-06-01 10:06:00Z])
      |> ViewModel.new()

    assert model.state_icons.recently_started == nil
  end

  test "aggregates node resource usage independently from the view model" do
    resources = ResourceSummary.aggregate(container_assigns().containers_extended)

    assert resources == %{
             cpu_usage: 12.5,
             used_memory: 1_500,
             io: 1_500,
             net: 3_000,
             cpu_count: 4,
             available_memory: 8_000,
             io_total: 3_000,
             net_total: 7_000
           }
  end

  defp container_assigns do
    %{
      summary_type: :containers,
      nodename: "node-a",
      node_metadata: %{"platform" => "linux/amd64"},
      node_info: %{
        containers: %{
          running: %{
            stacks_count: 2,
            containers_count: 3,
            counters: %{
              status: status_counts(errored: 1, unknown: 0, outdated: 1, updated: 1),
              priority: %{ignore: 0, low: 0, normal: 1, high: 1, to_update: 0}
            }
          },
          combined: %{restarting?: true, latest_started_at: ~U[2026-06-01 09:55:00Z]}
        },
        images: %{
          combined: %{
            images_count: 4,
            total_bytesize: 2_048,
            counters: %{status: status_counts(locked: 1, unused: 2, in_use: 1)}
          }
        }
      },
      containers_extended: %{
        {"app", "id"} => %{
          resources: %Resources{
            records: [
              %Resources.Record{
                time: ~U[2026-06-01 10:00:00Z],
                cpu_count: 4,
                cpu_usage: 12.5,
                used_memory: 1_500,
                available_memory: 8_000,
                io: %{read: 1_000, write: 2_000},
                net: %{rx: 3_000, tx: 4_000}
              }
            ],
            rates: %Rates{
              cpu_usage: 12.5,
              used_memory: 1_500,
              io: %{read: 1_000, write: 500},
              net: %{rx: 1_000, tx: 2_000}
            }
          }
        }
      },
      node_settings: %{web_ui: "https://node-a.test"},
      clock_now: ~U[2026-06-01 10:00:00Z],
      fetch_staleness: :fresh,
      since_last_fetch: "2 seconds"
    }
  end

  defp status_counts(counts) do
    Map.new(counts, fn {status, count} -> {status, %{count: count, percentage: 0.0}} end)
  end
end
