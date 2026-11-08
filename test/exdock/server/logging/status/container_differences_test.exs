defmodule Exdock.Server.Logging.Status.ContainerDifferencesTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Logging.Status.ContainerDifferences

  test "reports state changes, new containers, vanished containers, and fetch errors" do
    before = %{
      "node_a" => [
        {"same", {:before, true}},
        {"started", {:before, false}},
        {"stopped", {:before, true}},
        {"vanished", {:before, true}}
      ],
      "node_b" => [{"unchanged", {:before, false}}]
    }

    response = %{
      "node_a" => [
        {"same", {:ok, true}},
        {"started", {:ok, true}},
        {"stopped", {:ok, false}},
        {"new", {:ok, true}},
        {"errored", {:timeout, false}}
      ],
      "node_b" => [{"unchanged", {:ok, false}}]
    }

    assert ContainerDifferences.calculate(before, response) == %{
             "node_a" => [
               {"errored", {:error, :timeout}},
               {"new", {:new, true}},
               {"started", {:ok, true}},
               {"stopped", {:ok, false}},
               {"vanished", {:ok, :vanished}}
             ]
           }
  end

  test "treats a missing node response as vanished containers" do
    assert ContainerDifferences.calculate(%{"node" => [{"app", {:before, true}}]}, %{}) == %{
             "node" => [{"app", {:ok, :vanished}}]
           }
  end

  test "matches canonical node keys across snapshots" do
    assert ContainerDifferences.calculate(
             %{"node" => [{"app", {:before, true}}, {"gone", {:before, false}}]},
             %{"node" => [{"app", {:ok, true}}, {"new", {:ok, false}}]}
           ) == %{
             "node" => [{"gone", {:ok, :vanished}}, {"new", {:new, false}}]
           }
  end

  test "returns an empty map when every container is unchanged" do
    before = %{"node" => [{"app", {:before, true}}]}
    response = %{"node" => [{"app", {:ok, true}}]}

    assert ContainerDifferences.calculate(before, response) == %{}
  end
end
