defmodule Exdock.ClientLib.Async do
  @moduledoc """
  In-memory registry for pending async batches.

  Batches are grouped by job name and resource id, which lets several polling
  jobs of the same type run independently while still being easy to replace or
  remove when a newer refresh schedules updated work.
  """

  alias Exdock.ClientLib.Async

  defstruct [
    :jobs
  ]

  @type t :: %__MODULE__{
          jobs: %{atom() => %{String.t() => Async.Batch.t()}}
        }

  @spec new() :: t()
  def new(), do: %__MODULE__{jobs: %{}}

  @spec set(t(), Async.Batch.t()) :: t()
  def set(%__MODULE__{jobs: jobs} = state, %Async.Batch{name: name, id: id} = batch)
      when is_atom(name) and is_binary(id) do
    jobs = Map.update(jobs, name, %{id => batch}, fn existing -> Map.put(existing, id, batch) end)
    %{state | jobs: jobs}
  end

  @spec get(t(), atom(), String.t()) :: Async.Batch.t() | nil
  def get(%__MODULE__{jobs: jobs}, name, id) when is_atom(name) and is_binary(id) do
    jobs
    |> Map.get(name, %{})
    |> Map.get(id, nil)
  end

  @spec remove(t(), Async.Batch.t()) :: t()
  def remove(%__MODULE__{jobs: jobs} = state, %Async.Batch{name: name, id: id}) do
    jobs = Map.update(jobs, name, %{}, fn existing -> Map.delete(existing, id) end)
    %{state | jobs: jobs}
  end
end
