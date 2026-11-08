defmodule Exdock.Docker.Local.ImagePullTest do
  use ExUnit.Case, async: true

  alias Exdock.Docker.Local.ImagePull
  alias Exdock.Docker.Local.ImagePullTransportFake
  alias Exdock.Docker.Error

  test "retains request failures that arrive before the session starts", %{task_supervisor: supervisor} do
    consumer = start_supervised!({Agent, fn -> nil end})
    task = Task.Supervisor.async_nolink(supervisor, fn -> exit(:request_crashed) end)
    monitor = Process.monitor(task.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000

    session = ImagePull.Session.new("repo/crashed:latest", consumer, supervisor, task, 1_000)
    assert {:error, %Error{cause: :request_crashed}} = ImagePull.Session.await(session)
  end

  setup do
    task_supervisor = start_supervised!({Task.Supervisor, []})
    %{task_supervisor: task_supervisor}
  end

  test "runs the transport under the supplied task supervisor", %{task_supervisor: task_supervisor} do
    conn = %{owner: self(), outcome: :success}

    assert {:ok, "repo/app:latest"} =
             ImagePull.run(conn, "repo/app:latest", nil, nil,
               transport: ImagePullTransportFake,
               task_supervisor: task_supervisor,
               timeout: 1_000
             )

    assert_receive {:image_pull_request_started, request_pid, "repo/app:latest", consumer}, 1_000
    assert is_pid(request_pid)
    assert is_pid(consumer)
    refute request_pid == self()
  end

  test "returns transport startup errors", %{task_supervisor: task_supervisor} do
    conn = %{owner: self(), outcome: {:error, :econnrefused}}

    assert {:error,
            %Error{
              operation: {:image_pull, :stream_request},
              cause: :econnrefused,
              retryable?: true
            }} =
             ImagePull.run(conn, "repo/missing:latest", nil, nil,
               transport: ImagePullTransportFake,
               task_supervisor: task_supervisor,
               timeout: 1_000
             )
  end

  test "cleans up the consumer when the request supervisor is full", %{task_supervisor: supervisor} do
    full_supervisor = start_supervised!({Task.Supervisor, max_children: 0}, id: :full_requests)
    conn = %{owner: self(), outcome: :success}
    opts = [transport: ImagePullTransportFake, task_supervisor: full_supervisor, timeout: 1_000]

    assert {:error, %Error{operation: {:image_pull, :request_start}}} =
             ImagePull.run(conn, "repo/full:latest", nil, nil, opts)

    assert {:ok, "repo/full:latest"} =
             ImagePull.run(conn, "repo/full:latest", nil, nil, Keyword.put(opts, :task_supervisor, supervisor))
  end

  test "terminates supervised requests that exceed the pull timeout", %{
    task_supervisor: task_supervisor
  } do
    conn = %{owner: self(), outcome: :wait}

    pull_task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        ImagePull.run(conn, "repo/slow:latest", nil, nil,
          transport: ImagePullTransportFake,
          task_supervisor: task_supervisor,
          timeout: 100
        )
      end)

    assert_receive {:image_pull_request_started, request_pid, "repo/slow:latest", _consumer}, 1_000
    monitor = Process.monitor(request_pid)

    assert {:error,
            %Error{
              operation: :image_pull,
              cause: :timeout,
              message: "Image pull timed out",
              retryable?: true
            }} = Task.await(pull_task, 1_000)

    assert_receive {:DOWN, ^monitor, :process, ^request_pid, _reason}, 1_000
  end

  test "retains an abnormal request exit as the typed cause", %{task_supervisor: task_supervisor} do
    conn = %{owner: self(), outcome: {:exit, :request_crashed}}

    assert {:error,
            %Error{
              operation: {:image_pull, :request},
              cause: :request_crashed,
              message: "Image pull request exited"
            }} =
             ImagePull.run(conn, "repo/crashed:latest", nil, nil,
               transport: ImagePullTransportFake,
               task_supervisor: task_supervisor,
               timeout: 1_000
             )
  end
end
