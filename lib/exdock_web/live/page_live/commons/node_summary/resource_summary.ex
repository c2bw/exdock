defmodule ExdockWeb.Commons.NodeSummary.ResourceSummary do
  @moduledoc """
  Aggregates container resource samples into node-level presentation rows.

  Missing samples remain `nil` so the UI can distinguish unavailable data from
  a measured zero. Capacity values use the largest reported node total while
  usage and transfer values are summed across containers.
  """

  alias Exdock.ReadModel.Container
  alias Exdock.Size
  alias ExdockWeb.Format

  @type t :: %{
          cpu_usage: number() | nil,
          used_memory: number() | nil,
          io: number() | nil,
          net: number() | nil,
          cpu_count: number() | nil,
          available_memory: number() | nil,
          io_total: number() | nil,
          net_total: number() | nil
        }

  @spec rows(map()) :: [[map()]]
  def rows(containers_extended) when is_map(containers_extended) do
    resources = aggregate(containers_extended)

    [
      [
        metric(
          "hero-cpu-chip",
          "CPU",
          Format.percentage(resources.cpu_usage),
          available_cpu(resources.cpu_count)
        ),
        metric(
          "hero-server",
          "I/O",
          Size.human_readable(resources.io, decimals: 1, time_unit: "/s"),
          cumulative_total(resources.io_total)
        )
      ],
      [
        metric(
          "hero-chart-bar-square",
          "RAM",
          Size.human_readable(resources.used_memory, decimals: 1),
          available_memory(resources.available_memory)
        ),
        metric(
          "hero-wifi",
          "NET",
          Size.human_readable(resources.net, decimals: 1, time_unit: "/s"),
          cumulative_total(resources.net_total)
        )
      ]
    ]
  end

  @spec aggregate(map()) :: t()
  def aggregate(containers_extended) when is_map(containers_extended) do
    Enum.reduce(containers_extended, empty(), fn {_key, container}, totals ->
      resources = container.resources
      rates = resources.rates
      latest = Container.latest_resources(resources)

      %{
        cpu_usage: optional_sum(totals.cpu_usage, rates.cpu_usage),
        used_memory: optional_sum(totals.used_memory, rates.used_memory),
        io: optional_sum(totals.io, Container.resource_aggregate(resources, :io)),
        net: optional_sum(totals.net, Container.resource_aggregate(resources, :net)),
        cpu_count: optional_max(totals.cpu_count, latest && latest.cpu_count),
        available_memory: optional_max(totals.available_memory, latest && latest.available_memory),
        io_total: optional_sum(totals.io_total, record_total(latest, :io)),
        net_total: optional_sum(totals.net_total, record_total(latest, :net))
      }
    end)
  end

  defp empty do
    %{
      cpu_usage: nil,
      used_memory: nil,
      io: nil,
      net: nil,
      cpu_count: nil,
      available_memory: nil,
      io_total: nil,
      net_total: nil
    }
  end

  defp metric(icon, label, value, detail),
    do: %{icon: icon, label: label, value: value, detail: detail}

  defp available_cpu(nil), do: "Total unavailable"
  defp available_cpu(count), do: "#{count} CPUs available"

  defp available_memory(nil), do: "Total unavailable"

  defp available_memory(bytes),
    do: "#{Size.human_readable(bytes, decimals: 1)} available"

  defp cumulative_total(nil), do: "Total unavailable"
  defp cumulative_total(bytes), do: "#{Size.human_readable(bytes, decimals: 1)} total"

  defp record_total(nil, _field), do: nil

  defp record_total(record, field) do
    record
    |> Map.fetch!(field)
    |> Map.values()
    |> Enum.sum()
  end

  defp optional_max(nil, nil), do: nil
  defp optional_max(nil, value), do: value
  defp optional_max(value, nil), do: value
  defp optional_max(left, right), do: max(left, right)

  defp optional_sum(nil, nil), do: nil
  defp optional_sum(nil, value), do: value
  defp optional_sum(value, nil), do: value
  defp optional_sum(left, right), do: left + right
end
