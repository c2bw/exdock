defmodule Exdock.Container.RuntimeState do
  @moduledoc """
  Shared policy for deriving a container's presentation runtime state.

  The policy accepts the current time explicitly so callers and tests do not
  need to race the system clock around the just-started cutoff.
  """

  @just_started_cutoff_seconds 60 * 10

  @type t :: :just_started | :running | nil

  @spec of(DateTime.t() | nil, DateTime.t()) :: t()
  def of(started_at, now \\ DateTime.utc_now())
  def of(nil, %DateTime{}), do: nil

  def of(%DateTime{} = started_at, %DateTime{} = now) do
    if DateTime.diff(now, started_at, :second) >= @just_started_cutoff_seconds,
      do: :running,
      else: :just_started
  end
end
