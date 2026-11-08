defmodule Exdock.Datetime.Duration do
  @moduledoc """
  Calculates compact, human-readable durations between datetimes.
  """

  alias Exdock.Datetime.Format

  @type time_unit :: :day | :hour | :minute | :second

  @duration_units [
    {:day, 24 * 60 * 60, "d"},
    {:hour, 60 * 60, "h"},
    {:minute, 60, "m"},
    {:second, 1, "s"}
  ]

  @spec elapsed_since(DateTime.t() | String.t() | nil, DateTime.t()) :: String.t()
  def elapsed_since(datetime, since \\ DateTime.utc_now())
  def elapsed_since(nil, _since), do: ""

  def elapsed_since(datetime, %DateTime{} = since) when is_binary(datetime) do
    datetime
    |> Format.from_string()
    |> format_elapsed_since(since)
  end

  def elapsed_since(%DateTime{} = datetime, %DateTime{} = since) do
    since
    |> DateTime.diff(datetime, :second)
    |> max(1)
    |> duration_parts()
    |> format_duration_parts()
  end

  @spec duration_until(DateTime.t(), DateTime.t()) :: String.t()
  def duration_until(%DateTime{} = to, %DateTime{} = now \\ DateTime.utc_now()) do
    elapsed_since(now, to)
  end

  @spec simple_diff(DateTime.t(), DateTime.t(), time_unit()) :: String.t()
  def simple_diff(
        %DateTime{} = timestamp,
        %DateTime{} = since \\ DateTime.utc_now(),
        stop_at \\ :minute
      )
      when stop_at in [:day, :hour, :minute, :second] do
    diff_in_unit(timestamp, since, :day, stop_at)
  end

  defp format_elapsed_since(nil, _since), do: ""

  defp format_elapsed_since(%DateTime{} = datetime, %DateTime{} = since) do
    elapsed_since(datetime, since)
  end

  defp duration_parts(total_seconds) when is_integer(total_seconds) and total_seconds > 0 do
    total_seconds
    |> split_duration_units()
    |> elem(0)
  end

  defp split_duration_units(total_seconds) do
    Enum.map_reduce(@duration_units, total_seconds, fn {unit, unit_seconds, suffix}, remaining ->
      value = div(remaining, unit_seconds)
      {{unit, value, suffix}, rem(remaining, unit_seconds)}
    end)
  end

  defp format_duration_parts(parts) do
    parts
    |> Enum.reject(fn {_unit, value, _suffix} -> value == 0 end)
    |> Enum.map_join(" ", fn {_unit, value, suffix} -> "#{value}#{suffix}" end)
  end

  defp diff_in_unit(%DateTime{} = timestamp, %DateTime{} = since, diff_unit, stop_at) do
    case DateTime.diff(since, timestamp, diff_unit) do
      0 when diff_unit != stop_at ->
        diff_in_unit(timestamp, since, smaller_time_unit(diff_unit), stop_at)

      value ->
        "#{value}#{time_unit_label(diff_unit)}"
    end
  end

  defp time_unit_label(:day), do: "d"
  defp time_unit_label(:hour), do: "h"
  defp time_unit_label(:minute), do: "m"
  defp time_unit_label(:second), do: "s"

  defp smaller_time_unit(:day), do: :hour
  defp smaller_time_unit(:hour), do: :minute
  defp smaller_time_unit(:minute), do: :second
end
