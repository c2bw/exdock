defmodule Exdock.Server.State.Storage.Persistence.Result do
  @moduledoc """
  Normalizes low-level persistence outcomes at the storage boundary.
  """

  alias Exdock.Server.State.Storage.Persistence.Error

  @spec normalize_insert_result({:ok, term()} | {:error, term()}, atom()) ::
          :ok | {:error, Error.t()}
  def normalize_insert_result({:ok, _record}, _step), do: :ok

  def normalize_insert_result({:error, error}, step),
    do: {:error, Error.new(step, error)}

  @spec normalize_write_result(
          :ok | {:ok, term()} | {non_neg_integer(), term()} | {:error, term()},
          atom() | module()
        ) :: :ok | {:error, Error.t()}
  def normalize_write_result(:ok, _operation), do: :ok
  def normalize_write_result({:ok, _value}, _operation), do: :ok
  def normalize_write_result({count, _rows}, _operation) when is_integer(count) and count >= 0, do: :ok

  def normalize_write_result({:error, reason}, operation),
    do: {:error, Error.new(operation, reason)}

  @spec require_loaded(term() | nil, atom(), term()) :: {:ok, term()} | {:error, Error.t()}
  def require_loaded(nil, operation, cause) when is_atom(operation),
    do: {:error, Error.new(operation, cause)}

  def require_loaded(value, _operation, _cause), do: {:ok, value}
end
