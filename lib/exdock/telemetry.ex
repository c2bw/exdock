defmodule Exdock.Telemetry do
  @moduledoc "Public access to runtime telemetry measurements."

  alias Exdock.Server.TelemetryReporter

  @spec measurement([atom()]) :: {:ok, map()} | {:error, term()}
  def measurement(event_name), do: TelemetryReporter.get_measurement(event_name)
end
