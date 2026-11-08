defmodule Exdock.Server.State.Storage.Settings.Importer.Report do
  @moduledoc """
  Summary of a completed settings import.

  `applied` counts persisted entries by configuration section. `skipped` is the
  number of plan warnings retained in `warnings`, so callers can distinguish a
  complete import from a compatible partial import.
  """

  alias Exdock.Server.State.Storage.Settings.Importer.Plan

  @enforce_keys [:applied, :skipped, :warnings]
  defstruct [:applied, :skipped, :warnings]

  @type t :: %__MODULE__{
          applied: %{Plan.field() => non_neg_integer()},
          skipped: non_neg_integer(),
          warnings: [Plan.warning()]
        }

  @spec from_plan(Plan.t()) :: t()
  def from_plan(%Plan{sections: sections, warnings: warnings}) do
    %__MODULE__{
      applied: Map.new(sections, fn {field, entries} -> {field, entry_count(entries)} end),
      skipped: length(warnings),
      warnings: warnings
    }
  end

  defp entry_count(entries) when is_list(entries), do: length(entries)
  defp entry_count(entries) when is_map(entries), do: map_size(entries)
end
