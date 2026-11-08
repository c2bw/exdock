defmodule Exdock.ClientLib.Async.Scheduler do
  @moduledoc """
  Owns batch generations and schedules the next sample only after completion.

  Replacing a batch invalidates its previous results and timers. The process
  owner keeps any active sample until it finishes, then starts the newest batch.
  """

  alias Exdock.ClientLib.Async

  @spec add(Async.t(), Async.Batch.t()) :: Async.t()
  def add(async_jobs, %Async.Batch{} = batch) do
    batch = %{batch | generation: make_ref()}
    schedule(batch, 0)
    Async.set(async_jobs, batch)
  end

  @spec tick(Async.t(), Async.Batch.t()) :: {Async.t(), Async.Batch.t() | nil}
  def tick(async_jobs, %Async.Batch{name: name, id: id, generation: generation}) do
    case Async.get(async_jobs, name, id) do
      %Async.Batch{generation: ^generation, count: count} = batch when count > 0 ->
        {batch, run?, delay} = Async.Batch.run(batch, DateTime.utc_now())
        if not run?, do: schedule(batch, delay)
        {Async.set(async_jobs, batch), if(run?, do: batch)}

      _stale_or_finished ->
        {async_jobs, nil}
    end
  end

  @spec complete(Async.t(), Async.Batch.t()) :: Async.t()
  def complete(async_jobs, %Async.Batch{name: name, id: id, generation: generation}) do
    case Async.get(async_jobs, name, id) do
      %Async.Batch{generation: ^generation, count: 0} = batch ->
        Async.remove(async_jobs, batch)

      %Async.Batch{generation: ^generation} = batch ->
        schedule(batch, batch.interval)
        async_jobs

      %Async.Batch{} = replacement ->
        schedule(replacement, 0)
        async_jobs

      nil ->
        async_jobs
    end
  end

  defp schedule(batch, delay), do: Process.send_after(self(), {:run_async_batch, batch}, delay)
end
