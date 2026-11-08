defmodule Exdock.Server.Jobs.TaskStreamTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.TaskStream

  test "collects successful values in stream order" do
    assert %TaskStream{values: [:first, :second], exits: []} =
             TaskStream.collect([{:ok, :first}, {:ok, :second}])
  end

  test "retains partial values and normalizes worker exits" do
    report = TaskStream.collect([{:ok, :first}, {:exit, :killed}, {:ok, :second}])

    assert %TaskStream{
             values: [:first, :second],
             exits: [{:task_exit, :killed}]
           } = report

    assert {:error, {:task_exit, :killed}, [:first, :second]} = TaskStream.result(report)
  end

  test "normalizes task timeouts" do
    assert %TaskStream{exits: [:timeout]} = TaskStream.collect([{:exit, {:timeout, :details}}])
  end
end
