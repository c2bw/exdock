defmodule Exdock.Server.State.Storage.Persistence.BatchWriter do
  @moduledoc false

  alias Exdock.Server.State.Storage.Persistence.Error

  @spec persist_each(Enumerable.t(), (term() -> :ok | {:error, term()})) ::
          :ok | {:error, term()}
  def persist_each(records, persist) when is_function(persist, 1) do
    Exdock.Result.each(records, persist)
  end

  @spec insert_rows(
          Enumerable.t(),
          (term() -> term()),
          ([term()] -> :ok | {:error, term()}),
          atom()
        ) :: :ok | {:error, Error.t()}
  def insert_rows(records, to_row, insert_all, operation)
      when is_function(to_row, 1) and is_function(insert_all, 1) and is_atom(operation) do
    result = records |> Enum.map(to_row) |> insert_all.()

    case result do
      :ok -> :ok
      {:error, reason} -> {:error, Error.new(operation, reason)}
    end
  end

  @spec sync_set(
          {non_neg_integer(), nil | [term()]} | {:error, term()},
          atom()
        ) :: :ok | {:error, Error.t()}
  def sync_set({count, _rows}, _operation) when is_integer(count), do: :ok

  def sync_set({:error, reason}, operation) when is_atom(operation),
    do: {:error, Error.new(operation, reason)}
end
