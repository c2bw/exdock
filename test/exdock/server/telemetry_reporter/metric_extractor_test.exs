defmodule Exdock.Server.TelemetryReporter.MetricExtractorTest do
  use ExUnit.Case, async: true

  import Telemetry.Metrics

  alias Exdock.Server.TelemetryReporter.MetricExtractor

  test "extracts non-counter metric values with their metric type" do
    metrics = [summary("phoenix.live_view.render.stop.duration")]

    assert [{42, :duration, :summary}] =
             MetricExtractor.extract(metrics, %{duration: 42}, %{})
  end

  test "skips counters and metrics rejected by keep predicates" do
    metrics = [
      counter("phoenix.live_view.render.stop.count"),
      summary("phoenix.live_view.render.stop.duration",
        keep: fn metadata -> metadata.keep? end
      )
    ]

    assert [] = MetricExtractor.extract(metrics, %{duration: 42, count: 1}, %{keep?: false})
  end

  test "skips metrics whose callbacks raise" do
    metrics = [
      summary("phoenix.live_view.render.stop.duration",
        measurement: fn _measurements -> raise "bad measurement" end
      ),
      summary("phoenix.live_view.render.stop.duration",
        keep: fn _metadata -> raise "bad keep" end
      )
    ]

    assert [] = MetricExtractor.extract(metrics, %{duration: 42}, %{})
  end
end
