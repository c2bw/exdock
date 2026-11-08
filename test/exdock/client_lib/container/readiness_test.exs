defmodule Exdock.ClientLib.Container.ReadinessTest do
  use ExUnit.Case, async: true
  alias Exdock.ClientLib.Container.Recreator.Readiness

  test "waits for a healthy replacement" do
    inspect =
      sequence([
        {:ok, %{State: %{Status: "running", Health: %{Status: "starting"}}}},
        {:ok, %{State: %{Status: "running", Health: %{Status: "healthy"}}}}
      ])

    assert :ok = Readiness.await(inspect, readiness_interval: 0)
  end

  test "an early process exit without a healthcheck fails verification" do
    inspect =
      sequence([
        {:ok, %{State: %{Status: "running", StartedAt: "first"}}},
        {:ok, %{State: %{Status: "exited"}}}
      ])

    assert {:error, :replacement_not_running} = Readiness.await(inspect, readiness_interval: 0)
  end

  test "running containers without a healthcheck pass after the grace period" do
    inspect = fn -> {:ok, %{State: %{Status: "running", StartedAt: "same"}}} end
    assert :ok = Readiness.await(inspect, readiness_grace: 2, readiness_interval: 1)
  end

  test "an inspect request cannot exceed the readiness deadline" do
    owner = self()

    inspect = fn ->
      send(owner, {:inspecting, self()})

      receive do
        :never_sent -> {:ok, %{}}
      end
    end

    assert {:error, :readiness_timeout} = Readiness.await(inspect, readiness_timeout: 50)
    assert_receive {:inspecting, pid}
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
  end

  test "optional verification can be disabled" do
    assert :ok = Readiness.await(fn -> flunk("unexpected inspect") end, readiness: false)
  end

  for {response, expected} <- [
        {{:ok, %{}}, :malformed_response},
        {{:ok, %{State: %{Status: "running", Health: %{Status: "unexpected"}}}}, :malformed_response},
        {{:error, :econnrefused}, :econnrefused}
      ] do
    @response response
    @expected expected
    test "propagates readiness failure #{inspect(expected)} for #{inspect(response)}" do
      assert {:error, @expected} = Readiness.await(fn -> @response end)
    end
  end

  defp sequence(responses) do
    agent = start_supervised!({Agent, fn -> responses end})
    fn -> Agent.get_and_update(agent, fn [response | rest] -> {response, rest} end) end
  end
end
