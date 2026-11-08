defmodule Exdock.Server.State.PeriodicJob do
  alias Exdock.Server.State.PeriodicJob.NextRun

  @moduledoc """
  Internal scheduler state for the periodic automation job.

  The struct keeps the configured cron expression plus the precomputed next run
  so schedule calculation remains a pure part of authoritative runtime state.
  """

  defstruct [
    :cron_string,
    :cron_expression,
    :next_run
  ]

  @type t :: %__MODULE__{
          cron_string: String.t(),
          cron_expression: Crontab.CronExpression.t(),
          next_run: DateTime.t() | nil
        }

  @default_cron_string "0 22 * * *"

  @doc """
  Create a new periodic job.

  Invalid syntax falls back to the default schedule. A parsed schedule with
  no future occurrence stays inactive, including after restoring stored settings.
  """
  @spec create(String.t()) :: t()
  def create(cron_string) when is_binary(cron_string) do
    case parse_cron(cron_string) do
      {:ok, expression} ->
        %__MODULE__{cron_string: cron_string, cron_expression: expression, next_run: next_run_datetime(expression)}

      {:error, _error} ->
        default_job()
    end
  end

  @doc """
  Replace the cron string of the periodic job.

  A replacement only takes effect when the cron string has a future occurrence.
  """
  @spec replace(t(), String.t()) :: {:ok, t()} | {:error, t()}
  def replace(%__MODULE__{} = periodic_job, cron_string) when is_binary(cron_string) do
    case build(cron_string, periodic_job) do
      {:ok, updated_job} -> {:ok, updated_job}
      {:error, _error, previous_job} -> {:error, previous_job}
    end
  end

  def set!(%__MODULE__{} = pj, cron_string) when is_binary(cron_string) do
    case build(cron_string, pj) do
      {:ok, updated_job} -> updated_job
      {:error, error, _previous_job} -> raise("Invalid cron string: #{error}")
    end
  end

  defp parse_cron(cron_string), do: Crontab.CronExpression.Parser.parse(cron_string)

  defp default_job, do: set!(%__MODULE__{}, @default_cron_string)

  defp build(cron_string, %__MODULE__{} = previous_job) when is_binary(cron_string) do
    with {:ok, expression} <- parse_cron(cron_string),
         %DateTime{} = next_run <- next_run_datetime(expression) do
      {:ok, %{assign_cron(previous_job, cron_string, expression) | next_run: next_run}}
    else
      {:error, error} -> {:error, error, previous_job}
      nil -> {:error, "no future occurrence", previous_job}
    end
  end

  defp assign_cron(%__MODULE__{} = pj, cron_string, %Crontab.CronExpression{} = expression) do
    %{pj | cron_string: cron_string, cron_expression: expression}
  end

  @spec set_next(t()) :: t()
  def set_next(%__MODULE__{} = pj) do
    %{pj | next_run: next_run_datetime(pj.cron_expression)}
  end

  @spec valid?(String.t()) :: boolean()
  def valid?(cron_string) when is_binary(cron_string) do
    match?(%DateTime{}, next_run(cron_string))
  end

  @spec next_run_datetime(Crontab.CronExpression.t()) :: DateTime.t() | nil
  defp next_run_datetime(%Crontab.CronExpression{} = cron_expr) do
    NextRun.resolve(cron_expr)
  end

  @doc false
  @spec next_run_datetime(Crontab.CronExpression.t(), DateTime.t(), String.t()) :: DateTime.t() | nil
  def next_run_datetime(
        %Crontab.CronExpression{} = cron_expr,
        %DateTime{} = now,
        timezone
      )
      when is_binary(timezone) do
    NextRun.resolve(cron_expr, now, timezone)
  end

  @doc """
  Returns the date of the next run.

  Returns nil when the cron string is invalid or has no future occurrence.
  """
  @spec next_run(String.t()) :: DateTime.t() | nil
  def next_run(cron_string) when is_binary(cron_string) do
    case parse_cron(cron_string) do
      {:ok, expr} -> next_run_datetime(expr)
      {:error, _error} -> nil
    end
  end

  @doc false
  @spec next_run(String.t(), DateTime.t(), String.t()) :: DateTime.t() | nil
  def next_run(cron_string, %DateTime{} = now, timezone)
      when is_binary(cron_string) and is_binary(timezone) do
    case parse_cron(cron_string) do
      {:ok, expr} -> next_run_datetime(expr, now, timezone)
      {:error, _error} -> nil
    end
  end
end
