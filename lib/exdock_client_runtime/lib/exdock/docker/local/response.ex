defmodule Exdock.Docker.Local.Response do
  @moduledoc """
  Normalizes responses returned by the generated Docker Engine client.

  The generated API reports both decoded model structs and raw HTTP responses
  through its success channel. These helpers keep acceptance rules explicit
  while exposing one consistent `{:ok, value}` / `{:error, reason}` contract.
  """

  alias Exdock.Docker.Local.{GeneratedResponse, Types}

  @spec expect_status(Types.result(term()), integer() | [integer()]) :: Types.result(term())
  def expect_status(result, status) when is_integer(status),
    do: expect_status(result, [status])

  def expect_status(result, statuses) when is_list(statuses) do
    normalize(result, fn
      response -> GeneratedResponse.status(response) in statuses
    end)
  end

  @spec expect_struct(Types.result(term()), module()) :: Types.result(term())
  def expect_struct(result, module) when is_atom(module) do
    normalize(result, &is_struct(&1, module))
  end

  @spec reject_struct(Types.result(term()), module()) :: Types.result(term())
  def reject_struct(result, module) when is_atom(module) do
    normalize(result, &(not is_struct(&1, module)))
  end

  @spec normalize(Types.result(term()), (term() -> boolean())) :: Types.result(term())
  def normalize({:ok, response}, accepted?) when is_function(accepted?, 1) do
    if accepted?.(response), do: {:ok, response}, else: {:error, response}
  end

  def normalize({:error, error}, accepted?) when is_function(accepted?, 1),
    do: {:error, error}
end
