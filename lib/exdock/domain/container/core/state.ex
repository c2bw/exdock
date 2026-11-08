defmodule Exdock.Domain.Container.Core.State do
  @moduledoc """
  Runtime state details copied from Docker's container inspect response.
  """

  require Logger

  @derive Jason.Encoder
  defstruct [
    :status,
    :running,
    :paused,
    :restarting,
    :oom_killed,
    :dead,
    :pid,
    :exit_code,
    :error,
    :started_at,
    :finished_at,
    :health
  ]

  @type t :: %__MODULE__{
          status: String.t() | nil,
          running: boolean() | nil,
          paused: boolean() | nil,
          restarting: boolean() | nil,
          oom_killed: boolean() | nil,
          dead: boolean() | nil,
          pid: integer() | nil,
          exit_code: integer() | nil,
          error: String.t() | nil,
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil,
          health: map() | nil
        }

  @spec new(map()) :: t()
  def new(%{
        "Status" => status,
        "Running" => running,
        "Paused" => paused,
        "Restarting" => restarting,
        "OOMKilled" => oom_killed,
        "Dead" => dead,
        "Pid" => pid,
        "ExitCode" => exit_code,
        "Error" => error,
        "StartedAt" => started_at,
        "FinishedAt" => finished_at,
        "Health" => health
      }) do
    %__MODULE__{
      status: status,
      running: running,
      paused: paused,
      restarting: restarting,
      oom_killed: oom_killed,
      dead: dead,
      pid: pid,
      exit_code: exit_code,
      error: error,
      started_at: parse_docker_timestamp(started_at),
      finished_at: parse_docker_timestamp(finished_at),
      health: durable_health(health)
    }
  end

  @doc """
  Restore timestamp types after encrypted JSON persistence has decoded them as
  ISO-8601 strings.
  """
  @spec from_persisted(t()) :: t()
  def from_persisted(%__MODULE__{} = state) do
    %{
      state
      | started_at: parse_timestamp(state.started_at),
        finished_at: parse_timestamp(state.finished_at),
        health: durable_health(state.health)
    }
  end

  @spec parse_docker_timestamp(String.t() | nil) :: DateTime.t() | nil
  defp parse_docker_timestamp(timestamp), do: parse_timestamp(timestamp)

  defp parse_timestamp(nil), do: nil
  defp parse_timestamp(%DateTime{} = timestamp), do: timestamp

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    # Docker inspect timestamps are ISO-8601 strings. Keep invalid values non-fatal
    # because runtime state should still be usable without a parsed timestamp.
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        Logger.warning("Container.core: invalid datetime format: #{inspect(timestamp)}")
        nil
    end
  end

  # Docker rotates health probe log entries continuously. Persist only the
  # health state used for durable change detection, not volatile probe history.
  defp durable_health(nil), do: nil

  defp durable_health(health) when is_map(health) do
    %{
      "Status" => Map.get(health, "Status"),
      "FailingStreak" => Map.get(health, "FailingStreak")
    }
  end
end
