defmodule Exdock.Domain.Container.Resources do
  alias Exdock.Domain.Container.Resources.Record
  alias Exdock.Domain.Container.Resources.Rates

  defstruct rates: %Rates{}, records: []

  @type t :: %__MODULE__{
          rates: Rates.t(),
          records: list(Record.t())
        }

  @record_len 10
  @record_seconds_cutoff 20

  @spec new() :: t()
  def new(), do: %__MODULE__{}

  @doc """
    Add a record to the resources.

    The record is added only if the record time is unique.
  """
  @spec add_record(nil, Record.t(), DateTime.t()) :: t()
  def add_record(nil, %Record{} = record, %DateTime{} = now), do: new() |> add_record(record, now)

  @spec add_record(t(), Record.t() | nil, DateTime.t()) :: t()
  def add_record(%__MODULE__{} = resources, nil, %DateTime{} = now),
    do: refresh_retained_samples(resources, now)

  @spec add_record(t(), Record.t(), DateTime.t()) :: t()
  def add_record(%__MODULE__{} = resources, %Record{} = record, %DateTime{} = now) do
    resources
    |> prepend_sample(record)
    |> refresh_retained_samples(now)
  end

  defp prepend_sample(%__MODULE__{records: records} = resources, %Record{} = record) do
    %{resources | records: [record | records]}
  end

  defp refresh_retained_samples(%__MODULE__{records: records} = resources, %DateTime{} = now) do
    # Keep only recent unique samples before recalculating rates; stale Docker
    # counters would distort throughput averages.
    retained_records = Record.filter(records, now, @record_seconds_cutoff, @record_len)
    %{resources | records: retained_records, rates: Rates.calculate(retained_records)}
  end

  @doc """
  Returns the latest record.
  """
  @spec latest(t()) :: Record.t() | nil
  def latest(%__MODULE__{records: []} = _resources), do: nil
  def latest(%__MODULE__{records: [h | _]} = _resources), do: h

  @spec calculate_aggregates(t() | nil, :io | :net) :: number() | nil
  def calculate_aggregates(nil, _type), do: nil
  def calculate_aggregates(%__MODULE__{rates: %Rates{} = rates}, type) when type in [:io, :net], do: Rates.aggregate(rates, type)

  # Docker stats arrive as a large ContainerStatsResponse, but this module only
  # persists a compact sample: read time, CPU counters, memory usage, cumulative
  # block IO bytes, and cumulative network bytes. Rates are derived from the
  # retained samples when a caller asks for aggregate resource usage.
end
