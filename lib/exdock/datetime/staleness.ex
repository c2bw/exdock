defmodule Exdock.Datetime.Staleness do
  @moduledoc """
  Classifies timestamps according to the application's freshness policy.
  """

  @type t :: :fresh | :stale | :old

  @fresh_for_seconds 5 * 60
  @old_after_seconds 12 * 60 * 60

  @spec classify(DateTime.t() | nil, DateTime.t()) :: t() | nil
  def classify(datetime, now \\ DateTime.utc_now())
  def classify(nil, %DateTime{}), do: nil

  def classify(%DateTime{} = datetime, %DateTime{} = now) do
    case DateTime.diff(now, datetime, :second) do
      elapsed when elapsed < @fresh_for_seconds -> :fresh
      elapsed when elapsed > @old_after_seconds -> :old
      _elapsed -> :stale
    end
  end
end
