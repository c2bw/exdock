defmodule Exdock.Server.Jobs.TaskStream do
  @moduledoc """
  Normalizes `Task.async_stream/3` outcomes without discarding partial work.

  Callers choose whether worker exits fail the whole operation or whether the
  successfully completed values remain useful.
  """

  defstruct values: [], exits: []

  @type t(value) :: %__MODULE__{
          values: [value],
          exits: [term()]
        }

  @spec collect(Enumerable.t()) :: t(term())
  def collect(outcomes) do
    outcomes
    |> Enum.reduce(%__MODULE__{}, fn
      {:ok, value}, report -> %{report | values: [value | report.values]}
      {:exit, reason}, report -> %{report | exits: [normalize_exit(reason) | report.exits]}
    end)
    |> reverse()
  end

  @spec result(t(value)) :: {:ok, [value]} | {:error, term(), [value]} when value: term()
  def result(%__MODULE__{values: values, exits: []}), do: {:ok, values}
  def result(%__MODULE__{values: values, exits: [reason | _]}), do: {:error, reason, values}

  defp reverse(report) do
    %{report | values: Enum.reverse(report.values), exits: Enum.reverse(report.exits)}
  end

  defp normalize_exit(:timeout), do: :timeout
  defp normalize_exit({:timeout, _details}), do: :timeout
  defp normalize_exit(reason), do: {:task_exit, reason}
end
