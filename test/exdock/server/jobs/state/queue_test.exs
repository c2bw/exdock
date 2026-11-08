defmodule Exdock.Server.Jobs.State.QueueTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.State.Queue

  test "select moves runnable details out of the queue in one pass" do
    instant = detail(:instant)
    blocked = detail({:finish, "previous"})

    queue =
      Queue.new()
      |> Queue.enqueue(blocked)
      |> Queue.enqueue(instant)
      |> Queue.select(:instant)

    assert %Queue{queue: [^blocked], runnable: [^instant]} = queue
    assert {%Queue{runnable: []}, [^instant]} = Queue.pop(queue)
  end

  test "select appends newly runnable details after existing ones" do
    first = detail(:instant, name: :first)
    second = detail(:instant, name: :second)

    queue =
      Queue.new()
      |> Queue.enqueue(first)
      |> Queue.select(:instant)
      |> Queue.enqueue(second)
      |> Queue.select(:instant)

    assert %Queue{queue: [], runnable: [^first, ^second]} = queue
    assert {%Queue{runnable: []}, [^first, ^second]} = Queue.pop(queue)
  end

  test "drain_runnable_for selects and clears a runnable batch in one call" do
    instant = detail(:instant)
    blocked = detail({:finish, "previous"})

    assert {%Queue{queue: [^blocked], runnable: []}, [^instant]} =
             Queue.new()
             |> Queue.enqueue(blocked)
             |> Queue.enqueue(instant)
             |> Queue.drain_runnable_for(:instant)
  end

  test "finish events honor success requirements" do
    upstream = detail(:instant)
    success_only = detail({:finish, upstream.id}, name: :success_only, requirements: :success)
    always = detail({:finish, upstream.id}, name: :always, requirements: :none)

    success_queue =
      Queue.new()
      |> Queue.enqueue(success_only)
      |> Queue.enqueue(always)
      |> Queue.select({:finish, upstream.id, nil})

    assert {%Queue{queue: []}, runnable} = Queue.pop(success_queue)
    assert Enum.sort(Enum.map(runnable, & &1.name)) == [:always, :success_only]

    failed_queue =
      Queue.new()
      |> Queue.enqueue(success_only)
      |> Queue.enqueue(always)
      |> Queue.select({:finish, upstream.id, :failed})

    assert {%Queue{queue: [^success_only]}, [^always]} = Queue.pop(failed_queue)
  end

  test "remove cascades through chained details that can no longer run" do
    upstream = detail(:instant)
    child = detail({:finish, upstream.id})
    grandchild = detail({:finish, child.id})
    unrelated = detail({:finish, "other"})

    queue =
      Queue.new()
      |> Queue.enqueue(unrelated)
      |> Queue.enqueue(grandchild)
      |> Queue.enqueue(child)
      |> Queue.remove(upstream.id)

    assert %Queue{queue: [^unrelated]} = queue
  end

  test "remove cascades across multiple children of the same blocked detail" do
    upstream = detail(:instant)
    child_a = detail({:finish, upstream.id}, name: :child_a)
    child_b = detail({:finish, upstream.id}, name: :child_b)
    grandchild = detail({:finish, child_b.id}, name: :grandchild)
    unrelated = detail({:finish, "other"}, name: :unrelated)

    queue =
      Queue.new()
      |> Queue.enqueue(unrelated)
      |> Queue.enqueue(grandchild)
      |> Queue.enqueue(child_b)
      |> Queue.enqueue(child_a)
      |> Queue.remove(upstream.id)

    assert %Queue{queue: [^unrelated]} = queue
  end

  defp detail(trigger, opts \\ []) do
    name = Keyword.get(opts, :name, name_for(trigger))
    requirements = Keyword.get(opts, :requirements, :none)
    spec = Jobs.Spec.new(Jobs.Spec.Local.new(fn _id -> :ok end), [], nil)

    Jobs.Detail.new(name, spec, trigger: trigger, requirements: requirements)
  end

  defp name_for(:instant), do: :instant
  defp name_for({:finish, _id}), do: :chained
end
