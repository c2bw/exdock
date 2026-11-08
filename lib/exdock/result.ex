defmodule Exdock.Result do
  @moduledoc """
  Small helpers for composing tagged results without losing input order.
  """

  @spec traverse(Enumerable.t(), (input -> {:ok, output} | {:error, reason})) ::
          {:ok, [output]} | {:error, reason}
        when input: term(), output: term(), reason: term()
  def traverse(values, mapper) when is_function(mapper, 1) do
    values
    |> reduce([], fn value, mapped ->
      with {:ok, result} <- mapper.(value), do: {:ok, [result | mapped]}
    end)
    |> reverse_success()
  end

  @spec reduce(Enumerable.t(), accumulator, (input, accumulator -> {:ok, accumulator} | {:error, reason})) ::
          {:ok, accumulator} | {:error, reason}
        when input: term(), accumulator: term(), reason: term()
  def reduce(values, initial, reducer) when is_function(reducer, 2) do
    Enum.reduce_while(values, {:ok, initial}, fn value, {:ok, accumulator} ->
      case reducer.(value, accumulator) do
        {:ok, next_accumulator} -> {:cont, {:ok, next_accumulator}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec each(Enumerable.t(), (input -> :ok | {:error, reason})) :: :ok | {:error, reason}
        when input: term(), reason: term()
  def each(values, operation) when is_function(operation, 1) do
    case reduce(values, :ok, fn value, :ok ->
           case operation.(value) do
             :ok -> {:ok, :ok}
             {:error, _reason} = error -> error
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp reverse_success({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_success({:error, _reason} = error), do: error
end
