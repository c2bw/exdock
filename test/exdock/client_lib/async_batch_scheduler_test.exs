defmodule Exdock.ClientLib.AsyncBatchSchedulerTest do
  use ExUnit.Case, async: false

  alias Exdock.AgentRuntime.Wire
  alias Exdock.ClientLib.{Async, AsyncBatchScheduler}

  setup context do
    start_supervised!({Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor})

    scheduler =
      start_supervised!(%{
        id: AsyncBatchScheduler,
        start:
          {AsyncBatchScheduler, :start_link, [{"node-a", self(), Wire}, [max_concurrency: Map.get(context, :max_concurrency, 8)]]}
      })

    %{scheduler: scheduler}
  end

  test "slow samples serialize while other containers continue", %{scheduler: scheduler} do
    owner = self()

    sample = fn ->
      send(owner, {:started, self()})

      receive do
        :finish -> {:ok, %{}}
      end
    end

    add(scheduler, "slow", 3, sample)
    assert_receive {:started, first}
    _ = :sys.get_state(scheduler)
    refute_receive {:started, _}, 20

    add(scheduler, "other", 1, fn -> {:ok, %{}} end)
    assert_sample("other")

    send(first, :finish)
    assert_sample("slow")
    assert_receive {:started, second}
    refute_receive {:started, _}, 20
    send(second, :finish)
    assert_sample("slow")
    assert_receive {:started, third}
    send(third, :finish)
    assert_sample("slow")
    assert :sys.get_state(scheduler).samples == %{}
    refute_receive {:started, _}, 20
  end

  test "refresh replacement waits for active sample and discards its stale result", %{scheduler: scheduler} do
    owner = self()

    add(scheduler, "app", 3, fn ->
      send(owner, {:old_sample, self()})

      receive do
        :finish -> {:ok, %{stale: true}}
      end
    end)

    assert_receive {:old_sample, old_worker}
    old_state = :sys.get_state(scheduler)
    stale_batch = Async.get(old_state.async_jobs, :container_resources, "app")

    add(scheduler, "app", 1, fn ->
      send(owner, :superseded_sample)
      {:ok, %{}}
    end)

    add(scheduler, "app", 1, fn ->
      send(owner, :latest_sample)
      {:ok, %{}}
    end)

    _ = :sys.get_state(scheduler)
    refute_receive :superseded_sample, 20
    refute_receive :latest_sample, 20
    send(old_worker, :finish)
    assert_receive :latest_sample
    assert_sample("app")
    refute_receive :superseded_sample, 20
    refute_receive {:"$gen_cast", {:client_message, {:resource_sample, _}}}, 20

    send(scheduler, {:run_async_batch, stale_batch})
    _ = :sys.get_state(scheduler)
    refute_receive {:old_sample, _}, 20
    assert :sys.get_state(scheduler).samples == %{}
  end

  test "worker crashes release the slot and allow a newer refresh", %{scheduler: scheduler} do
    owner = self()

    add(scheduler, "app", 3, fn ->
      send(owner, {:blocked, self()})

      receive do
        :unused -> {:ok, %{}}
      end
    end)

    assert_receive {:blocked, worker}
    add(scheduler, "app", 1, fn -> {:ok, %{}} end)
    _ = :sys.get_state(scheduler)
    ref = Process.monitor(worker)
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
    assert_sample("app")
    assert :sys.get_state(scheduler).samples == %{}
  end

  test "a failed sample does not prevent the next sample", %{scheduler: scheduler} do
    counter = start_supervised!({Agent, fn -> 0 end})

    sample = fn ->
      case Agent.get_and_update(counter, fn n -> {n, n + 1} end) do
        0 -> {:error, :timeout}
        1 -> {:ok, %{}}
      end
    end

    add(scheduler, "app", 2, sample)
    assert_sample("app")
    assert Agent.get(counter, & &1) == 2
    assert :sys.get_state(scheduler).samples == %{}
  end

  test "stopping the scheduler also stops blocked sample workers", %{scheduler: scheduler} do
    owner = self()

    add(scheduler, "app", 1, fn ->
      send(owner, {:blocked, self()})

      receive do
        :unused -> {:ok, %{}}
      end
    end)

    assert_receive {:blocked, worker}
    ref = Process.monitor(worker)
    GenServer.stop(scheduler)
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
  end

  @tag max_concurrency: 2
  test "queues distinct containers within the limit and replaces pending work", %{scheduler: scheduler} do
    owner = self()

    blocked = fn id ->
      fn ->
        send(owner, {:started, id, self()})

        receive do
          :finish -> {:ok, %{}}
        end
      end
    end

    add(scheduler, "a", 1, blocked.("a"))
    add(scheduler, "b", 1, blocked.("b"))
    assert_receive {:started, "a", a}
    assert_receive {:started, "b", b}
    for id <- ["c", "d", "e"], do: add(scheduler, id, 1, blocked.(id))
    _ = :sys.get_state(scheduler)
    assert map_size(:sys.get_state(scheduler).samples) == 2
    refute_receive {:started, _, _}, 20

    add(scheduler, "c", 1, fn ->
      send(owner, :latest_c)
      {:ok, %{}}
    end)

    _ = :sys.get_state(scheduler)
    send(a, :finish)
    assert_sample("a")
    assert_receive :latest_c
    assert_sample("c")
    assert_receive {:started, "d", d}
    assert map_size(:sys.get_state(scheduler).samples) == 2
    refute_receive {:started, "c", _}, 20

    monitor = Process.monitor(b)
    Process.exit(b, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^b, :killed}
    assert_receive {:started, "e", e}
    assert map_size(:sys.get_state(scheduler).samples) == 2
    send(d, :finish)
    send(e, :finish)
    assert_sample("d")
    assert_sample("e")
    state = :sys.get_state(scheduler)
    assert state.samples == %{}
    assert :queue.is_empty(state.pending)
    assert MapSet.size(state.queued) == 0
    assert state.async_jobs.jobs == %{container_resources: %{}}
  end

  defp add(scheduler, id, count, sample),
    do: GenServer.cast(scheduler, {:add, Async.Batch.new(:container_resources, id, count, 0, sample)})

  defp assert_sample(id) do
    assert_receive {:"$gen_cast",
                    {:client_message, {:resource_sample, %{"container_id" => ^id, "node" => "node-a", "sample" => sample}}}}

    assert sample == %{}
  end
end
