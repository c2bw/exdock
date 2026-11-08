defmodule Exdock.Server.TelemetryReporter.MeasurementWindow do
  @moduledoc """
  Maintains the bounded measurement history and derived event aggregates.
  """

  alias Exdock.Server.TelemetryReporter.MetricExtractor

  @phoenix_render_stop_event [:phoenix, :live_view, :render, :stop]
  @events_with_average MapSet.new([@phoenix_render_stop_event])
  @max_measurements 5

  @type stored_measurement :: %{
          raw: any(),
          e: [MetricExtractor.extracted_metric()]
        }
  @type t :: %{
          measurements: [stored_measurement()],
          average: number() | nil
        }

  @spec new() :: t()
  def new, do: %{measurements: [], average: nil}

  @spec record(t(), list(atom()), any(), [MetricExtractor.extracted_metric()]) :: t()
  def record(bucket, event_name, raw_measurements, extracted_metrics) do
    recent_measurements =
      [%{raw: raw_measurements, e: extracted_metrics} | bucket.measurements]
      |> Enum.take(@max_measurements)

    %{
      bucket
      | measurements: recent_measurements,
        average: calculate_average(event_name, recent_measurements)
    }
  end

  defp calculate_average(event_name, measurements) do
    if MapSet.member?(@events_with_average, event_name) do
      measurements
      |> Enum.flat_map(&extracted_measurement_values/1)
      |> average_numeric_values()
    end
  end

  defp extracted_measurement_values(%{e: extracted_metrics}) do
    Enum.map(extracted_metrics, fn {value, _measurement, _type} -> value end)
  end

  defp average_numeric_values([]), do: nil
  defp average_numeric_values(values), do: values |> Enum.sum() |> Kernel./(Enum.count(values)) |> trunc()
end
