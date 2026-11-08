defmodule Exdock.ResultTest do
  use ExUnit.Case, async: true

  alias Exdock.Result

  test "traverse preserves order" do
    assert {:ok, [2, 4, 6]} = Result.traverse([1, 2, 3], &{:ok, &1 * 2})
  end

  test "traverse stops at the first error" do
    owner = self()

    assert {:error, :invalid} =
             Result.traverse([1, 2, 3], fn value ->
               send(owner, {:visited, value})
               if value == 2, do: {:error, :invalid}, else: {:ok, value}
             end)

    assert_received {:visited, 1}
    assert_received {:visited, 2}
    refute_received {:visited, 3}
  end

  test "reduce threads successful accumulators and stops on errors" do
    assert {:ok, 6} = Result.reduce([1, 2, 3], 0, fn value, total -> {:ok, total + value} end)

    assert {:error, :invalid} =
             Result.reduce([1, 2, 3], 0, fn
               2, _total -> {:error, :invalid}
               value, total -> {:ok, total + value}
             end)
  end

  test "each normalizes successful traversal and preserves the first error" do
    owner = self()

    assert {:error, :invalid} =
             Result.each([1, 2, 3], fn value ->
               send(owner, {:visited, value})
               if value == 2, do: {:error, :invalid}, else: :ok
             end)

    assert_received {:visited, 1}
    assert_received {:visited, 2}
    refute_received {:visited, 3}
  end
end
