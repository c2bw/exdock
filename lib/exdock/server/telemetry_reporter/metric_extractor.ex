defmodule Exdock.Server.TelemetryReporter.MetricExtractor do
  @moduledoc """
  Safely extracts values from telemetry metric definitions.

  User-provided measurement and keep callbacks are isolated so one faulty
  diagnostic metric cannot crash the reporter.
  """

  @type extracted_metric :: {number(), any(), atom()}

  @spec extract([struct()], map(), map()) :: [extracted_metric()]
  def extract(metrics, measurements, metadata) when is_list(metrics) do
    Enum.flat_map(metrics, &extract_metric(&1, measurements, metadata))
  end

  defp extract_metric(%struct{} = metric, measurements, metadata) do
    with {:ok, measurement} when not is_nil(measurement) <-
           metric_measurement(metric, measurements, metadata),
         true <- report_metric?(metric, metadata) do
      [{measurement, metric.measurement, metric_type(struct)}]
    else
      _skip -> []
    end
  end

  defp report_metric?(%Telemetry.Metrics.Counter{}, _metadata), do: false
  defp report_metric?(metric, metadata), do: safe_keep?(metric, metadata)

  defp metric_measurement(metric, measurements, metadata) do
    {:ok, read_measurement(metric, measurements, metadata)}
  rescue
    _error -> :error
  end

  defp safe_keep?(%{keep: nil}, _metadata), do: true

  defp safe_keep?(metric, metadata) do
    metric.keep.(metadata)
  rescue
    _error -> false
  end

  defp read_measurement(metric, measurements, metadata) do
    case metric.measurement do
      fun when is_function(fun, 2) -> fun.(measurements, metadata)
      fun when is_function(fun, 1) -> fun.(measurements)
      key -> measurements[key]
    end
  end

  defp metric_type(Telemetry.Metrics.Counter), do: :counter
  defp metric_type(Telemetry.Metrics.Distribution), do: :distribution
  defp metric_type(Telemetry.Metrics.LastValue), do: :last_value
  defp metric_type(Telemetry.Metrics.Sum), do: :sum
  defp metric_type(Telemetry.Metrics.Summary), do: :summary
end
