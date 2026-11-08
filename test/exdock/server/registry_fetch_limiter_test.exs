defmodule Exdock.Server.RegistryFetchLimiterTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.RegistryFetchLimiter
  alias Exdock.Server.RegistryFetchLimiter.LeaseState
  alias Exdock.Server.RegistryFetchLimiter.LeaseState.{Bucket, Owner, Waiter}
  alias Regc.Oci.Error

  test "canonicalizes Docker Hub aliases into one endpoint" do
    for reference <- [
          "redis:latest",
          "docker.io/library/redis:latest",
          "index.docker.io/library/redis:latest",
          "registry-1.docker.io/library/redis:latest"
        ] do
      assert RegistryFetchLimiter.endpoint(reference) ==
               {:ok, {"https", "registry-1.docker.io"}}
    end
  end

  test "keeps schemes and custom registry ports in endpoint keys" do
    assert RegistryFetchLimiter.endpoint("http://localhost:5000/team/app:latest") ==
             {:ok, {"http", "localhost:5000"}}

    assert RegistryFetchLimiter.endpoint("https://registry.example:5443/team/app:latest") ==
             {:ok, {"https", "registry.example:5443"}}
  end

  test "returns the reference error for malformed image references" do
    assert {:error, %Error{code: :invalid_reference}} =
             RegistryFetchLimiter.endpoint("registry..example/team/app:latest")
  end

  test "lease state promotes FIFO waiters through explicit effects" do
    endpoint = {"https", "registry.example"}
    first_monitor = make_ref()
    second_monitor = make_ref()
    second_from = {self(), make_ref()}

    first = Waiter.new({self(), make_ref()}, first_monitor)
    second = Waiter.new(second_from, second_monitor)

    assert {:granted, first_lease, state} =
             LeaseState.acquire(LeaseState.new(), endpoint, first, 1)

    assert {:queued, state} =
             LeaseState.acquire(state, endpoint, second, 1)

    assert {state, effects} =
             LeaseState.release(state, endpoint, first_lease, 1)

    assert [
             {:demonitor, ^first_monitor},
             {:reply, ^second_from, second_lease}
           ] = effects

    assert state.monitors[second_monitor] ==
             {:owner, endpoint, second_lease}

    assert %Bucket{owners: %{^second_lease => %Owner{monitor: ^second_monitor}}} =
             state.buckets[endpoint]
  end

  test "serializes checks for Docker Hub aliases" do
    limiter = start_supervised!({RegistryFetchLimiter, name: nil})
    task_supervisor = start_supervised!({Task.Supervisor, []})

    first =
      start_check(
        task_supervisor,
        limiter,
        "docker.io/library/redis:latest",
        :first
      )

    assert_receive {:entered, :first, first_pid}, 1_000

    second =
      start_check(
        task_supervisor,
        limiter,
        "index.docker.io/library/alpine:latest",
        :second
      )

    refute_receive {:entered, :second, _pid}, 50
    send(first_pid, {:release, :first})

    assert Task.await(first) == {:finished, :first}
    assert_receive {:entered, :second, second_pid}, 1_000

    send(second_pid, {:release, :second})
    assert Task.await(second) == {:finished, :second}
  end

  test "allows checks for each distinct registry to run simultaneously" do
    limiter = start_supervised!({RegistryFetchLimiter, name: nil})
    task_supervisor = start_supervised!({Task.Supervisor, []})

    tasks =
      for registry_number <- 1..5 do
        start_check(
          task_supervisor,
          limiter,
          "registry#{registry_number}.example/team/app:latest",
          registry_number
        )
      end

    entered =
      for _registry_number <- 1..5, into: %{} do
        assert_receive {:entered, registry_number, pid}, 1_000
        {registry_number, pid}
      end

    assert MapSet.new(Map.keys(entered)) == MapSet.new(1..5)

    Enum.each(entered, fn {registry_number, pid} ->
      send(pid, {:release, registry_number})
    end)

    assert Enum.map(tasks, &Task.await/1) ==
             Enum.map(1..5, &{:finished, &1})
  end

  test "releases a lease when a check raises" do
    limiter = start_supervised!({RegistryFetchLimiter, name: nil})
    task_supervisor = start_supervised!({Task.Supervisor, []})
    owner = self()

    failed =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        RegistryFetchLimiter.run(
          "registry.example/team/failed:latest",
          fn ->
            send(owner, {:entered, :failed, self()})

            receive do
              :fail -> raise "registry failed"
            end
          end,
          limiter
        )
      end)

    assert_receive {:entered, :failed, failed_pid}, 1_000

    next =
      start_check(
        task_supervisor,
        limiter,
        "registry.example/team/next:latest",
        :next
      )

    refute_receive {:entered, :next, _pid}, 50
    send(failed_pid, :fail)

    assert {:exit, {%RuntimeError{message: "registry failed"}, _stacktrace}} =
             Task.yield(failed, 1_000)

    assert_receive {:entered, :next, next_pid}, 1_000

    send(next_pid, {:release, :next})
    assert Task.await(next) == {:finished, :next}
  end

  test "releases a lease when its caller is terminated" do
    limiter = start_supervised!({RegistryFetchLimiter, name: nil})
    task_supervisor = start_supervised!({Task.Supervisor, []})

    first =
      start_check(
        task_supervisor,
        limiter,
        "registry.example/team/first:latest",
        :first
      )

    assert_receive {:entered, :first, first_pid}, 1_000

    second =
      start_check(
        task_supervisor,
        limiter,
        "registry.example/team/second:latest",
        :second
      )

    refute_receive {:entered, :second, _pid}, 50

    Task.ignore(first)
    first_monitor = Process.monitor(first_pid)
    assert :ok = Task.Supervisor.terminate_child(task_supervisor, first_pid)
    assert_receive {:DOWN, ^first_monitor, :process, ^first_pid, :shutdown}, 1_000

    assert_receive {:entered, :second, second_pid}, 1_000
    send(second_pid, {:release, :second})
    assert Task.await(second) == {:finished, :second}
  end

  defp start_check(task_supervisor, limiter, image_reference, id) do
    owner = self()

    Task.Supervisor.async_nolink(task_supervisor, fn ->
      RegistryFetchLimiter.run(
        image_reference,
        fn ->
          send(owner, {:entered, id, self()})

          receive do
            {:release, ^id} -> {:finished, id}
          end
        end,
        limiter
      )
    end)
  end
end
