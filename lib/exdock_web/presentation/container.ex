defmodule ExdockWeb.Presentation.Container do
  @moduledoc """
  Pure presentation rules shared by container views.
  """

  alias Exdock.Datetime

  @epoch DateTime.from_unix!(0)

  @spec priority_class(1..5) :: String.t()
  def priority_class(priority) do
    case priority do
      1 -> "bg-priority-one"
      2 -> "bg-priority-two"
      3 -> "bg-priority-three"
      4 -> "bg-priority-four"
      5 -> "bg-priority-five"
    end
  end

  @spec container_name(String.t()) :: String.t()
  def container_name(name), do: truncate_middle(name, 30)

  @spec stack_name(String.t()) :: String.t()
  def stack_name(name), do: truncate_middle(name, 18)

  @spec image_tag(String.t()) :: String.t()
  def image_tag(tag), do: truncate_middle(tag, 30)

  @spec running_time(DateTime.t(), DateTime.t()) :: String.t()
  def running_time(~U[0001-01-01 00:00:00Z], %DateTime{}), do: "-"

  def running_time(%DateTime{} = change_at, %DateTime{} = fetched_at) do
    Datetime.simple_diff(change_at, fetched_at, :second)
  end

  @spec remote_build_available?(DateTime.t()) :: boolean()
  def remote_build_available?(%DateTime{} = remote_build_date) do
    DateTime.after?(remote_build_date, @epoch)
  end

  @spec build_age_days(DateTime.t(), DateTime.t()) :: integer()
  def build_age_days(%DateTime{} = local_build_date, %DateTime{} = remote_build_date) do
    remote_build_date
    |> DateTime.diff(local_build_date, :second)
    |> Kernel./(60 * 60 * 24)
    |> trunc()
  end

  @spec build_date_iso8601(DateTime.t()) :: String.t()
  def build_date_iso8601(%DateTime{} = build_date) do
    build_date
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  @spec truncate_middle(String.t(), pos_integer()) :: String.t()
  def truncate_middle(value, max_length)
      when is_binary(value) and is_integer(max_length) and max_length > 2 do
    content_length = max_length - 2
    half_length = trunc(content_length / 2)

    if String.length(value) > content_length do
      start = String.slice(value, 0, half_length)
      ending = String.slice(value, String.length(value) - half_length, half_length)
      "#{start}..#{ending}"
    else
      value
    end
  end
end
