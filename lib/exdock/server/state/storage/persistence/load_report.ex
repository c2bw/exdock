defmodule Exdock.Server.State.Storage.Persistence.LoadReport do
  @moduledoc """
  Describes a persistence hydration failure without discarding valid rows.

  Batch loaders return this report when a database read or one or more row
  hydrations fail. `values` contains the successfully hydrated records and
  `failures` retains every rejected row reason for diagnostics.
  """

  @enforce_keys [:operation, :failures]
  defstruct operation: nil, values: [], failures: []

  @type t(value) :: %__MODULE__{
          operation: atom(),
          values: [value],
          failures: [term()]
        }

  @spec new(atom(), term(), [term()]) :: t(term())
  def new(operation, failure, values \\ [])
      when is_atom(operation) and is_list(values) do
    %__MODULE__{operation: operation, values: values, failures: [failure]}
  end

  @spec from_results(atom(), [{:ok, value} | {:error, term()}]) ::
          {:ok, [value]} | {:error, t(value)}
        when value: term()
  def from_results(operation, results) when is_atom(operation) and is_list(results) do
    {values, failures} =
      Enum.reduce(results, {[], []}, fn
        {:ok, value}, {values, failures} -> {[value | values], failures}
        {:error, reason}, {values, failures} -> {values, [reason | failures]}
      end)

    values = Enum.reverse(values)

    case Enum.reverse(failures) do
      [] -> {:ok, values}
      failures -> {:error, %__MODULE__{operation: operation, values: values, failures: failures}}
    end
  end
end
