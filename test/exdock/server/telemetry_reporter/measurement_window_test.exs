defmodule Exdock.Server.TelemetryReporter.MeasurementWindowTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.TelemetryReporter.MeasurementWindow

  @render_event [:phoenix, :live_view, :render, :stop]

  test "retains only the five latest measurements and averages their extracted values" do
    window =
      Enum.reduce(10..60//10, MeasurementWindow.new(), fn value, window ->
        MeasurementWindow.record(window, @render_event, %{duration: value}, [
          {value, :duration, :summary}
        ])
      end)

    assert Enum.map(window.measurements, & &1.raw.duration) == [60, 50, 40, 30, 20]
    assert window.average == 40
  end

  test "does not aggregate events without an average policy" do
    window =
      MeasurementWindow.record(
        MeasurementWindow.new(),
        [:exdock, :repo, :query],
        %{duration: 10},
        [{10, :duration, :summary}]
      )

    assert [%{raw: %{duration: 10}}] = window.measurements
    assert window.average == nil
  end
end
