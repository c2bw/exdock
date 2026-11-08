defmodule ExdockWeb.PageLive.Utils.RenderStatistics do
  @moduledoc """
  Owns the render-statistics timer state for a LiveView process.

  Each scheduled message carries a token so a message that was already delivered
  when statistics were disabled cannot restart the timer.
  """

  @initial_delay 800
  @interval 8_000

  @enforce_keys [:ref, :token]
  defstruct [:ref, :token]

  @opaque t :: %__MODULE__{ref: reference(), token: reference()}

  @spec set(t() | nil, boolean()) :: t() | nil
  def set(nil, false), do: nil
  def set(%__MODULE__{} = timer, false), do: cancel(timer)
  def set(nil, true), do: schedule(@initial_delay)
  def set(%__MODULE__{} = timer, true), do: timer

  @doc """
  Consumes the current timer message and schedules the next sample.

  Messages from cancelled or superseded timers are reported as stale.
  """
  @spec advance(t() | nil, reference()) :: {:ok, t()} | :stale
  def advance(%__MODULE__{token: token}, token), do: {:ok, schedule(@interval)}
  def advance(_timer, _token), do: :stale

  defp schedule(delay) do
    token = make_ref()
    ref = Process.send_after(self(), {:gather_rendering_statistics, token}, delay)
    %__MODULE__{ref: ref, token: token}
  end

  defp cancel(%__MODULE__{ref: ref}) do
    Process.cancel_timer(ref, async: false, info: false)
    nil
  end
end
