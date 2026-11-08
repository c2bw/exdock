defmodule Exdock.Domain.Container.Resources.Record do
  @moduledoc """
  One normalized container resource sample.

  Record ordering and retention live here. Docker wire-format conversion is
  delegated to `Record.Parser`.
  """

  require Logger

  alias __MODULE__.Parser

  @derive Jason.Encoder
  defstruct [
    :time,
    :cpu_count,
    :cpu_usage,
    :used_memory,
    :available_memory,
    :io,
    :net
  ]

  @type t :: %__MODULE__{
          time: DateTime.t(),
          cpu_count: integer(),
          cpu_usage: float(),
          used_memory: integer(),
          available_memory: integer(),
          io: %{read: integer(), write: integer()},
          net: %{rx: integer(), tx: integer()}
        }

  @doc """
  Returns true if the record has been fetched recently.
  """
  @spec recent?(t(), DateTime.t(), integer()) :: boolean()
  def recent?(%__MODULE__{time: time}, %DateTime{} = now, seconds_cutoff)
      when is_integer(seconds_cutoff) do
    DateTime.diff(now, time, :second) < seconds_cutoff
  end

  @doc """
  Returns true when the first record is at least as recent as the second.
  """
  @spec compare(t(), t()) :: boolean()
  def compare(%__MODULE__{time: %DateTime{} = first}, %__MODULE__{
        time: %DateTime{} = second
      }) do
    DateTime.compare(first, second) != :lt
  end

  @doc """
  Returns the time difference in seconds between two records.
  """
  @spec time_gap(t(), t()) :: float()
  def time_gap(%__MODULE__{time: %DateTime{} = first}, %__MODULE__{
        time: %DateTime{} = second
      }) do
    DateTime.diff(first, second, :millisecond) / 1000
  end

  @doc """
  Returns the newest unique records within the retention window.
  """
  @spec filter([t()], DateTime.t(), integer(), integer()) :: [t()]
  def filter(records, %DateTime{} = now, seconds_cutoff, take_max) when is_list(records) do
    records
    |> Enum.uniq_by(& &1.time)
    |> Enum.filter(&recent?(&1, now, seconds_cutoff))
    |> Enum.sort(&compare(&1, &2))
    |> current_run()
    |> Enum.take(take_max)
  end

  @doc "Keeps samples after the most recent cumulative-counter reset, newest first."
  @spec current_run([t()]) :: [t()]
  def current_run([]), do: []
  def current_run([record]), do: [record]

  def current_run([recent, older | rest]) do
    reset? =
      Enum.any?([{:io, [:read, :write]}, {:net, [:rx, :tx]}], fn {field, keys} ->
        recent_totals = Map.fetch!(recent, field)
        older_totals = Map.fetch!(older, field)
        Enum.any?(keys, &(Map.fetch!(recent_totals, &1) < Map.fetch!(older_totals, &1)))
      end)

    if reset?, do: [recent], else: [recent | current_run([older | rest])]
  end

  @spec new(map()) :: t() | nil
  def new(response) when is_map(response) do
    case Parser.parse(response) do
      {:ok, attrs} ->
        struct!(__MODULE__, attrs)

      {:error, reason} ->
        Logger.warning("Failed to create resource record: #{inspect(reason)}")
        nil
    end
  end
end
