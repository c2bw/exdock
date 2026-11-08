defmodule Exdock.Domain.Container.Resources.Rates do
  alias Exdock.Domain.Container.Resources.Record

  @io_keys [:read, :write]
  @net_keys [:rx, :tx]

  @derive Jason.Encoder
  defstruct cpu_usage: nil,
            used_memory: nil,
            io: %{read: nil, write: nil},
            net: %{rx: nil, tx: nil}

  @type t :: %__MODULE__{
          cpu_usage: float() | nil,
          used_memory: integer() | nil,
          io: %{read: integer() | nil, write: integer() | nil},
          net: %{rx: integer() | nil, tx: integer() | nil}
        }

  def aggregate(%__MODULE__{net: net} = _rates, :net), do: aggregate_totals(net, @net_keys)
  def aggregate(%__MODULE__{io: io} = _rates, :io), do: aggregate_totals(io, @io_keys)

  @doc """
   Calculate the rates from a list of records.

   Assumes that the records are ordered from the most recent to the oldest.
  """
  @spec calculate([Record.t()]) :: t()
  def calculate([]), do: %__MODULE__{}
  def calculate([%Record{cpu_usage: cpu_usage, used_memory: used_memory}]), do: build_from_single_sample(cpu_usage, used_memory)

  def calculate(records) when is_list(records) do
    case Record.current_run(records) do
      [record] -> calculate([record])
      current_records -> build_from_sample_window(current_records, sample_window(current_records))
    end
  end

  defp build_from_sample_window(records, window) when is_list(records) do
    throughput_rates = throughput_rates(window)

    build(
      average_field(records, :cpu_usage),
      average_field(records, :used_memory),
      throughput_rates.io,
      throughput_rates.net
    )
  end

  defp sample_window([recent | _] = records) do
    oldest = List.last(records)

    %{
      recent: recent,
      oldest: oldest,
      time_gap: Record.time_gap(recent, oldest)
    }
  end

  defp build_from_single_sample(cpu_usage, used_memory) do
    %__MODULE__{cpu_usage: cpu_usage, used_memory: used_memory}
  end

  defp build(cpu_usage, used_memory, io_rates, net_rates) do
    %__MODULE__{
      cpu_usage: cpu_usage,
      used_memory: trunc(used_memory),
      io: truncate_rates(io_rates, @io_keys),
      net: truncate_rates(net_rates, @net_keys)
    }
  end

  defp aggregate_totals(rate_group, keys) do
    totals = Enum.map(keys, &Map.fetch!(rate_group, &1))

    if complete_totals?(totals) do
      Enum.sum(totals)
    else
      nil
    end
  end

  defp complete_totals?(totals), do: Enum.all?(totals, &(&1 != nil))

  defp truncate_rates(rates, keys), do: Map.new(keys, &truncated_rate(rates, &1))

  defp truncated_rate(rates, key), do: {key, rates |> Map.fetch!(key) |> trunc()}

  defp average_field(records, field) do
    records
    |> Enum.map(&Map.fetch!(&1, field))
    |> Enum.sum()
    |> Kernel./(length(records))
  end

  defp throughput_rates(%{recent: recent, oldest: oldest, time_gap: time_gap}) do
    %{
      io: per_second_rates(recent.io, oldest.io, time_gap, @io_keys),
      net: per_second_rates(recent.net, oldest.net, time_gap, @net_keys)
    }
  end

  # Docker's IO/network counters are cumulative. Convert oldest-to-newest deltas
  # into per-second rates for the selected sample window.
  defp per_second_rates(recent_totals, old_totals, time_gap, keys) when time_gap > 0 do
    Map.new(keys, &per_second_rate(&1, recent_totals, old_totals, time_gap))
  end

  # If sample timestamps are identical, avoid division-by-zero and emit zero rates.
  defp per_second_rates(_recent_totals, _old_totals, _time_gap, keys) do
    Map.new(keys, fn key -> {key, 0} end)
  end

  defp per_second_rate(key, recent_totals, old_totals, time_gap) do
    delta = Map.fetch!(recent_totals, key) - Map.fetch!(old_totals, key)

    {key, delta / time_gap}
  end
end
