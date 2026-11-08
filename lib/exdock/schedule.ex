defmodule Exdock.Schedule do
  @moduledoc "Public schedule calculations used by delivery layers."

  alias Exdock.{Server.State.PeriodicJob, Timezone}

  @spec next_run(String.t()) :: DateTime.t() | nil
  def next_run(cron_string), do: PeriodicJob.next_run(cron_string)

  @spec next_run(String.t(), DateTime.t()) :: DateTime.t() | nil
  def next_run(cron_string, %DateTime{} = now),
    do: next_run(cron_string, now, Timezone.user_timezone())

  @doc false
  @spec next_run(String.t(), DateTime.t(), String.t()) :: DateTime.t() | nil
  def next_run(cron_string, %DateTime{} = now, timezone) when is_binary(timezone),
    do: PeriodicJob.next_run(cron_string, now, timezone)

  @spec valid?(String.t()) :: boolean()
  def valid?(cron_string), do: PeriodicJob.valid?(cron_string)
end
