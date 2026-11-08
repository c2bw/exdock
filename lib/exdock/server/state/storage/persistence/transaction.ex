defmodule Exdock.Server.State.Storage.Persistence.Transaction do
  @moduledoc """
  Shared transaction control for storage operations.

  Callers return ordinary `:ok`, `{:ok, value}`, or `{:error, reason}` values;
  this boundary alone translates failures into `Repo.rollback/1`.
  """

  alias Exdock.Repo
  alias Exdock.Server.State.Storage.Persistence.BatchWriter

  @type operation_result(value) :: :ok | {:ok, value} | {:error, term()}

  @spec run((-> operation_result(value))) :: {:ok, value | :ok} | {:error, term()}
        when value: term()
  def run(operation) when is_function(operation, 0) do
    Repo.transaction(fn ->
      case operation.() do
        :ok -> :ok
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec run_each(Enumerable.t(), (term() -> :ok | {:error, term()})) ::
          :ok | {:error, term()}
  def run_each(records, persist) when is_function(persist, 1) do
    case run(fn -> BatchWriter.persist_each(records, persist) end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec reduce(Enumerable.t(), accumulator, (term(), accumulator -> {:ok, accumulator} | {:error, term()})) ::
          {:ok, accumulator} | {:error, term()}
        when accumulator: term()
  def reduce(records, initial, reduce_step) when is_function(reduce_step, 2) do
    Exdock.Result.reduce(records, initial, reduce_step)
  end
end
