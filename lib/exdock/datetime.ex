defmodule Exdock.Datetime do
  @moduledoc """
  Stable facade for datetime formatting and application time policies.
  """

  alias Exdock.Datetime.Duration
  alias Exdock.Datetime.Format
  alias Exdock.Datetime.Staleness
  alias Exdock.ReadModel.Node

  @type staleness :: Staleness.t()
  @type time_unit :: Duration.time_unit()

  @spec get_node_last_fetch(Node.node_map(), Node.node_key()) :: DateTime.t() | nil
  defdelegate get_node_last_fetch(nodes, node), to: Node, as: :last_fetch

  @spec elapsed_since(DateTime.t() | String.t() | nil, DateTime.t()) :: String.t()
  def elapsed_since(datetime, since \\ DateTime.utc_now()) do
    Duration.elapsed_since(datetime, since)
  end

  @spec duration_until(DateTime.t()) :: String.t()
  defdelegate duration_until(to), to: Duration

  @spec duration_until(DateTime.t(), DateTime.t()) :: String.t()
  defdelegate duration_until(to, now), to: Duration

  @spec simple_diff(DateTime.t(), DateTime.t(), time_unit()) :: String.t()
  def simple_diff(timestamp, since \\ DateTime.utc_now(), stop_at \\ :minute) do
    Duration.simple_diff(timestamp, since, stop_at)
  end

  @spec elapsed_to_staleness(DateTime.t() | nil) :: staleness() | nil
  defdelegate elapsed_to_staleness(datetime), to: Staleness, as: :classify

  @spec elapsed_to_staleness(DateTime.t() | nil, DateTime.t()) :: staleness() | nil
  defdelegate elapsed_to_staleness(datetime, now), to: Staleness, as: :classify

  @spec utc_to_timezone(DateTime.t()) :: DateTime.t()
  defdelegate utc_to_timezone(datetime), to: Format

  @spec prettify(DateTime.t(), Format.precision()) :: String.t()
  def prettify(datetime, truncate \\ :second), do: Format.prettify(datetime, truncate)

  @spec from_string(String.t()) :: DateTime.t() | nil
  defdelegate from_string(datetime_string), to: Format

  @spec as_string(DateTime.t() | nil) :: String.t() | nil
  defdelegate as_string(datetime), to: Format

  @spec unix_epoch() :: DateTime.t()
  defdelegate unix_epoch(), to: Format

  @spec maybe_datetime!(String.t() | DateTime.t()) :: DateTime.t()
  defdelegate maybe_datetime!(datetime), to: Format
end
