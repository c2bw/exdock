defmodule Exdock.Domain.Container.Resources.Record.Parser do
  @moduledoc """
  Converts Docker container-stat payloads into validated resource attributes.

  Docker exposes CPU, block-I/O, and network values as cumulative counters.
  This parser normalizes those wire values into one compact point-in-time
  sample while preserving explicit error reasons for malformed required data.
  """

  @empty_io %{read: 0, write: 0}
  @empty_net %{rx: 0, tx: 0}

  @type attrs :: %{
          time: DateTime.t(),
          cpu_count: integer(),
          cpu_usage: float(),
          used_memory: integer(),
          available_memory: integer(),
          io: %{read: integer(), write: integer()},
          net: %{rx: integer(), tx: integer()}
        }

  @spec parse(map()) :: {:ok, attrs()} | {:error, term()}
  def parse(response) when is_map(response) do
    with {:ok, sample} <- compact_sample(response),
         {:ok, time} <- parse_read_time(sample.read_time),
         {:ok, cpu_usage} <- cpu_usage_percent(sample.cpu_counters) do
      {:ok, build_attrs(time, sample, cpu_usage)}
    end
  end

  defp compact_sample(%{
         "read" => read_time,
         "memory_stats" => memory_stats,
         "cpu_stats" => cpu_stats,
         "precpu_stats" => previous_cpu_stats,
         "blkio_stats" => blkio_stats,
         "networks" => networks
       }) do
    with {:ok, {used_memory, available_memory}} <- memory_counters(memory_stats),
         {:ok, cpu_counters} <- cpu_counter_delta_inputs(cpu_stats, previous_cpu_stats) do
      {:ok,
       %{
         read_time: read_time,
         used_memory: used_memory,
         available_memory: available_memory,
         cpu_counters: cpu_counters,
         io_entries: io_entries(blkio_stats),
         networks: networks
       }}
    end
  end

  defp compact_sample(_response), do: {:error, :invalid_stats_response}

  defp memory_counters(%{"usage" => usage, "limit" => limit})
       when is_integer(usage) and is_integer(limit),
       do: {:ok, {usage, limit}}

  defp memory_counters(_memory_stats), do: {:error, :invalid_memory_stats}

  defp cpu_counter_delta_inputs(
         %{
           "cpu_usage" => %{"total_usage" => total_usage},
           "system_cpu_usage" => system_usage,
           "online_cpus" => cpu_count
         },
         %{
           "cpu_usage" => %{"total_usage" => previous_total_usage},
           "system_cpu_usage" => previous_system_usage
         }
       )
       when is_integer(total_usage) and is_integer(previous_total_usage) and
              is_integer(system_usage) and is_integer(previous_system_usage) and
              is_integer(cpu_count) do
    {:ok,
     %{
       total_usage: total_usage,
       previous_total_usage: previous_total_usage,
       system_usage: system_usage,
       previous_system_usage: previous_system_usage,
       count: cpu_count
     }}
  end

  defp cpu_counter_delta_inputs(_cpu_stats, _previous_cpu_stats),
    do: {:error, :invalid_cpu_stats}

  defp parse_read_time(read_time) when is_binary(read_time) do
    case DateTime.from_iso8601(read_time) do
      {:ok, time, _offset} -> {:ok, time}
      {:error, reason} -> {:error, {:invalid_read_time, reason}}
    end
  end

  defp parse_read_time(read_time), do: {:error, {:invalid_read_time, read_time}}

  defp cpu_usage_percent(%{
         total_usage: total_usage,
         previous_total_usage: previous_total_usage,
         system_usage: system_usage,
         previous_system_usage: previous_system_usage,
         count: cpu_count
       }) do
    cpu_delta = total_usage - previous_total_usage
    system_delta = system_usage - previous_system_usage

    cond do
      system_delta <= 0 -> {:error, {:invalid_cpu_delta, system_delta}}
      cpu_count <= 0 -> {:error, {:invalid_cpu_count, cpu_count}}
      true -> {:ok, cpu_delta / system_delta * cpu_count * 100.0}
    end
  end

  defp build_attrs(time, sample, cpu_usage) do
    %{
      time: time,
      cpu_count: sample.cpu_counters.count,
      cpu_usage: cpu_usage,
      used_memory: sample.used_memory,
      available_memory: sample.available_memory,
      io: io_totals(sample.io_entries),
      net: network_totals(sample.networks)
    }
  end

  defp io_entries(%{"io_service_bytes_recursive" => entries}), do: entries
  defp io_entries(_blkio_stats), do: nil

  defp io_totals(entries) when is_list(entries),
    do: Enum.reduce(entries, @empty_io, &sum_io_entry/2)

  defp io_totals(_entries), do: @empty_io

  defp sum_io_entry(%{"op" => "read", "value" => value}, totals)
       when is_integer(value),
       do: increment_total(totals, :read, value)

  defp sum_io_entry(%{"op" => "write", "value" => value}, totals)
       when is_integer(value),
       do: increment_total(totals, :write, value)

  defp sum_io_entry(_entry, totals), do: totals

  defp network_totals(networks) when is_map(networks) do
    networks
    |> Map.values()
    |> Enum.reduce(@empty_net, &sum_network_entry/2)
  end

  defp network_totals(_networks), do: @empty_net

  defp sum_network_entry(%{"rx_bytes" => rx, "tx_bytes" => tx}, totals)
       when is_integer(rx) and is_integer(tx) do
    totals
    |> increment_total(:rx, rx)
    |> increment_total(:tx, tx)
  end

  defp sum_network_entry(_network, totals), do: totals

  defp increment_total(totals, key, value),
    do: Map.update!(totals, key, &(&1 + value))
end
