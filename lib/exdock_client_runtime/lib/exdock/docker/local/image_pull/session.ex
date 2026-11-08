defmodule Exdock.Docker.Local.ImagePull.Session do
  @moduledoc """
  Tracks the request and consumer lifecycle for one streamed image pull.

  A session keeps one deadline across both phases: while the transport request
  is running and while the consumer is finishing the last streamed messages.
  """

  alias Exdock.Docker.Error

  @enforce_keys [
    :image_tag,
    :consumer_pid,
    :task_supervisor,
    :task_pid,
    :monitor,
    :deadline
  ]
  defstruct [
    :image_tag,
    :consumer_pid,
    :task_supervisor,
    :task_pid,
    :monitor,
    :deadline,
    phase: :request_running
  ]

  @type phase :: :request_running | :consumer_finishing

  @type t :: %__MODULE__{
          image_tag: String.t(),
          consumer_pid: pid(),
          task_supervisor: Supervisor.supervisor(),
          task_pid: pid(),
          monitor: reference(),
          deadline: integer(),
          phase: phase()
        }

  @spec new(String.t(), pid(), Supervisor.supervisor(), Task.t(), non_neg_integer()) :: t()
  def new(image_tag, consumer_pid, task_supervisor, %Task{pid: task_pid, ref: monitor}, timeout) do
    %__MODULE__{
      image_tag: image_tag,
      consumer_pid: consumer_pid,
      task_supervisor: task_supervisor,
      task_pid: task_pid,
      monitor: monitor,
      deadline: System.monotonic_time(:millisecond) + timeout
    }
  end

  @spec await(t()) :: {:ok, String.t()} | {:error, Error.t()}
  def await(%__MODULE__{} = session) do
    remaining = max(session.deadline - System.monotonic_time(:millisecond), 0)

    receive do
      :image_pull_complete ->
        demonitor_request(session)
        {:ok, session.image_tag}

      {:image_pull_error, reason} ->
        demonitor_request(session)
        {:error, normalize_error(reason)}

      {monitor, _request_reply} when monitor == session.monitor ->
        demonitor_request(session)
        await(%{session | phase: :consumer_finishing})

      {:DOWN, monitor, :process, task_pid, reason}
      when monitor == session.monitor and task_pid == session.task_pid and
             reason == :normal ->
        await(%{session | phase: :consumer_finishing})

      {:DOWN, monitor, :process, task_pid, reason}
      when monitor == session.monitor and task_pid == session.task_pid ->
        stop_consumer(session.consumer_pid)
        {:error, Error.new({:image_pull, :request}, reason, message: "Image pull request exited")}
    after
      remaining -> timeout(session)
    end
  end

  defp timeout(%__MODULE__{phase: :request_running} = session) do
    Task.Supervisor.terminate_child(session.task_supervisor, session.task_pid)
    timeout_consumer(session)
  end

  defp timeout(%__MODULE__{phase: :consumer_finishing} = session),
    do: timeout_consumer(session)

  defp timeout_consumer(session) do
    demonitor_request(session)
    stop_consumer(session.consumer_pid)
    {:error, Error.new(:image_pull, :timeout, message: "Image pull timed out")}
  end

  defp demonitor_request(%__MODULE__{phase: :request_running, monitor: monitor}) do
    Process.demonitor(monitor, [:flush])

    receive do
      {^monitor, _request_reply} -> :ok
    after
      0 -> :ok
    end
  end

  defp demonitor_request(%__MODULE__{phase: :consumer_finishing}), do: :ok

  defp stop_consumer(consumer_pid) do
    GenServer.stop(consumer_pid, :normal)
  catch
    :exit, _reason -> :ok
  end

  defp normalize_error(%Error{} = error), do: error
  defp normalize_error(reason), do: Error.new(:image_pull, reason)
end
