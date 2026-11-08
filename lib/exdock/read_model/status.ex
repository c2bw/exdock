defmodule Exdock.ReadModel.Status do
  @moduledoc "Public status-query helpers for delivery layers."

  alias Exdock.Status.Dashboard.Row

  @spec active_job_count(map()) :: non_neg_integer()
  def active_job_count(%{jobs: jobs}), do: map_size(jobs)

  @spec errors?(map()) :: boolean()
  def errors?(%{dash: dash}), do: contains_error_state?(dash)

  defp contains_error_state?({:error, _reason}), do: true
  defp contains_error_state?(%Row{} = row), do: Row.attention?(row)

  defp contains_error_state?(value) when is_map(value),
    do: Enum.any?(value, fn {_key, nested} -> contains_error_state?(nested) end)

  defp contains_error_state?(_value), do: false
end
