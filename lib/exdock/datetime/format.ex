defmodule Exdock.Datetime.Format do
  @moduledoc """
  Parses, converts, and serializes datetimes for application display.
  """

  alias Exdock.Timezone

  @type precision :: :microsecond | :millisecond | :second

  @spec utc_to_timezone(DateTime.t(), String.t()) :: DateTime.t()
  def utc_to_timezone(%DateTime{} = utc_datetime, timezone \\ Timezone.user_timezone()) do
    case DateTime.shift_zone(utc_datetime, timezone) do
      {:ok, shifted} -> shifted
      {:error, _reason} -> utc_datetime
    end
  end

  @spec prettify(DateTime.t(), precision()) :: String.t()
  def prettify(%DateTime{} = datetime, truncate \\ :second) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(truncate)
    |> NaiveDateTime.to_string()
  end

  @spec from_string(String.t()) :: DateTime.t() | nil
  def from_string(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  @spec as_string(DateTime.t() | nil, String.t()) :: String.t() | nil
  def as_string(datetime, timezone \\ Timezone.user_timezone())
  def as_string(nil, _timezone), do: nil

  def as_string(%DateTime{} = datetime, timezone) do
    datetime
    |> utc_to_timezone(timezone)
    |> prettify()
  end

  @spec unix_epoch() :: DateTime.t()
  def unix_epoch do
    {:ok, unix_epoch} = DateTime.from_unix(0)
    unix_epoch
  end

  @spec maybe_datetime!(String.t() | DateTime.t()) :: DateTime.t()
  def maybe_datetime!(%DateTime{} = datetime), do: datetime

  def maybe_datetime!(datetime) when is_binary(datetime) do
    case from_string(datetime) do
      nil -> raise ArgumentError, "Invalid datetime string: #{datetime}"
      parsed -> parsed
    end
  end
end
