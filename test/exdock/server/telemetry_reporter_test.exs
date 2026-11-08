defmodule Exdock.Server.TelemetryReporterTest do
  use ExUnit.Case, async: true

  import Telemetry.Metrics
  alias Exdock.Server.TelemetryReporter

  @event_name [:phoenix, :live_view, :render, :stop]

  setup do
    token = make_ref()

    reporter =
      start_supervised!(
        {TelemetryReporter,
         name: nil,
         metrics: [
           summary("phoenix.live_view.render.stop.duration",
             unit: {:native, :millisecond},
             keep: fn metadata -> metadata[:reporter_token] == token end
           )
         ],
         wanted_events: [@event_name]}
      )

    %{reporter: reporter, reporter_token: token}
  end

  describe "get_measurement/1" do
    test "returns the supervised LiveView render measurement bucket", %{reporter: reporter} do
      assert {:ok, %{measurements: measurements, average: average}} =
               TelemetryReporter.get_measurement(@event_name, reporter)

      assert is_list(measurements)
      assert is_nil(average) or is_integer(average)
    end

    test "averages the five most recent extracted LiveView render measurements", %{
      reporter: reporter,
      reporter_token: token
    } do
      for duration <- native_durations([10, 20, 30, 40, 50]) do
        :telemetry.execute(@event_name, %{duration: duration}, %{reporter_token: token})
      end

      :sys.get_state(reporter)

      assert {:ok, %{measurements: measurements, average: 30}} =
               TelemetryReporter.get_measurement(@event_name, reporter)

      assert [
               %{e: [{50.0, _, :summary}]},
               %{e: [{40.0, _, :summary}]},
               %{e: [{30.0, _, :summary}]},
               %{e: [{20.0, _, :summary}]},
               %{e: [{10.0, _, :summary}]}
             ] = measurements
    end
  end

  defp native_durations(milliseconds) do
    Enum.map(milliseconds, &System.convert_time_unit(&1, :millisecond, :native))
  end
end
