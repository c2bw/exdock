defmodule Exdock.Server.Jobs.State.Queue do
  @moduledoc """
  Queue of job details waiting for their start trigger.

  Details move from `queue` to `runnable` when `select/2` sees a matching event.
  `pop/1` hands runnable details to the dispatcher and clears the runnable list.
  """

  alias Exdock.Server.Jobs

  defstruct queue: [],
            runnable: []

  @type t :: %__MODULE__{
          queue: list(Jobs.Detail.t()),
          runnable: list(Jobs.Detail.t())
        }

  @spec new() :: t()
  def new(), do: %__MODULE__{}

  @spec enqueue(t(), Jobs.Detail.t()) :: t()
  def enqueue(%__MODULE__{queue: queue} = state, %Jobs.Detail{} = detail) do
    %{state | queue: [detail | queue]}
  end

  @doc """
  Remove queued jobs chained to a completed id that did not become runnable.

  This cascades through dependent jobs so a failed or discarded upstream detail
  also removes downstream details that would otherwise wait forever.
  """
  @spec remove(t(), String.t()) :: t()
  def remove(%__MODULE__{queue: queue} = state, id) when is_binary(id) do
    %{state | queue: prune_blocked_chain(queue, [id])}
  end

  @doc """
  Select jobs whose trigger matches the event and remove them from the queue.

  Selected details are appended to the runnable list until `pop/1` hands them to
  the dispatcher.
  """
  @spec select(t(), Jobs.Detail.start_event()) :: t()
  def select(%__MODULE__{queue: queue, runnable: runnable} = state, event) do
    {released_details, still_waiting} = partition_released_details(queue, event)

    %{state | queue: still_waiting, runnable: runnable ++ released_details}
  end

  @doc """
  Return runnable jobs and clear the runnable list.
  """
  @spec pop(t()) :: {t(), list(Jobs.Detail.t())}
  def pop(%__MODULE__{runnable: runnable} = state) do
    {clear_runnable(state), runnable}
  end

  @doc """
  Move matching queued details to runnable, return them, and clear runnable.

  This is the dispatcher-facing operation: events release queued details, then
  the dispatcher immediately consumes the runnable batch.
  """
  @spec drain_runnable_for(t(), Jobs.Detail.start_event()) :: {t(), list(Jobs.Detail.t())}
  def drain_runnable_for(%__MODULE__{} = state, event) do
    state
    |> select(event)
    |> pop()
  end

  defp partition_released_details(queue, event) do
    Enum.split_with(queue, &Jobs.Detail.runnable?(&1, event))
  end

  defp prune_blocked_chain(queue, []), do: queue

  defp prune_blocked_chain(queue, [blocked_id | remaining_blocked_ids]) do
    # A removed detail can have its own descendants. Keep newly blocked ids in a
    # worklist so dependency cleanup is iterative and cannot leave orphan chains.
    {blocked_details, still_waiting} = Enum.split_with(queue, &depends_on?(&1, blocked_id))

    still_waiting
    |> prune_blocked_chain(remaining_blocked_ids ++ detail_ids(blocked_details))
  end

  defp clear_runnable(%__MODULE__{} = state), do: %{state | runnable: []}

  defp detail_ids(details), do: Enum.map(details, & &1.id)

  @spec depends_on?(Jobs.Detail.t(), String.t()) :: boolean()
  defp depends_on?(%Jobs.Detail{} = detail, id), do: Jobs.Detail.finish_trigger?(detail, id)
end
