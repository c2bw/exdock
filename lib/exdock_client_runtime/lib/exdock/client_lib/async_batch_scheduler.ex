defmodule Exdock.ClientLib.AsyncBatchScheduler do
  @moduledoc false

  use GenServer
  require Logger

  alias Exdock.ClientLib.Async
  alias Exdock.ClientLib.Async.Scheduler
  alias Exdock.Protocol.Message, as: ProtocolMessage

  defstruct node: nil,
            owner: nil,
            wire: nil,
            async_jobs: nil,
            samples: %{},
            max_concurrency: 8,
            pending: :queue.new(),
            queued: MapSet.new()

  @type t :: %__MODULE__{
          node: String.t(),
          owner: pid(),
          wire: module(),
          async_jobs: Async.t(),
          samples: %{reference() => %{task: Task.t(), batch: Async.Batch.t()}},
          max_concurrency: pos_integer(),
          pending: :queue.queue(),
          queued: MapSet.t()
        }

  def start_link(args, opts \\ []) do
    {limit, opts} = Keyword.pop(opts, :max_concurrency, 8)
    {node, owner, wire} = args
    GenServer.start_link(__MODULE__, {node, owner, wire, limit}, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec add(Async.Batch.t()) :: :ok
  def add(batch), do: GenServer.cast(__MODULE__, {:add, batch})

  @impl true
  def init({node, owner, wire, limit}) when is_integer(limit) and limit > 0 do
    Process.flag(:trap_exit, true)
    {:ok, %__MODULE__{node: node, owner: owner, wire: wire, async_jobs: Async.new(), max_concurrency: limit}}
  end

  @impl true
  def handle_cast({:add, %Async.Batch{} = batch}, state) do
    {:noreply, %{state | async_jobs: Scheduler.add(state.async_jobs, batch)}}
  end

  @impl true
  def handle_info({:run_async_batch, %Async.Batch{name: name, id: id} = batch}, state) do
    current = Async.get(state.async_jobs, name, id)

    cond do
      is_nil(current) or current.generation != batch.generation -> {:noreply, state}
      busy?(state, name, id) -> {:noreply, state}
      map_size(state.samples) >= state.max_concurrency -> {:noreply, enqueue(state, {name, id})}
      true -> {:noreply, run_sample(state, batch)}
    end
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    case Map.pop(state.samples, ref) do
      {nil, _samples} ->
        {:noreply, state}

      {%{batch: batch}, samples} ->
        Process.demonitor(ref, [:flush])
        publish_current_sample(state, batch, result)
        {:noreply, drain(%{state | samples: samples, async_jobs: Scheduler.complete(state.async_jobs, batch)})}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.samples, ref) do
      {nil, _samples} ->
        {:noreply, state}

      {%{batch: batch}, samples} ->
        Logger.warning("Async.Response [#{batch.name}] worker exited: #{inspect(reason)}")
        {:noreply, drain(%{state | samples: samples, async_jobs: Scheduler.complete(state.async_jobs, batch)})}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.samples, fn {_ref, %{task: task}} -> Task.shutdown(task, :brutal_kill) end)
  end

  defp busy?(state, name, id),
    do: Enum.any?(state.samples, fn {_ref, sample} -> sample.batch.name == name and sample.batch.id == id end)

  defp enqueue(state, key) do
    if MapSet.member?(state.queued, key),
      do: state,
      else: %{state | pending: :queue.in(key, state.pending), queued: MapSet.put(state.queued, key)}
  end

  defp drain(state) when map_size(state.samples) >= state.max_concurrency, do: state

  defp drain(state) do
    case :queue.out(state.pending) do
      {:empty, _} ->
        state

      {{:value, {name, id} = key}, pending} ->
        state = %{state | pending: pending, queued: MapSet.delete(state.queued, key)}
        batch = Async.get(state.async_jobs, name, id)
        state = if batch && not busy?(state, name, id), do: run_sample(state, batch), else: state
        drain(state)
    end
  end

  defp run_sample(state, batch) do
    {async_jobs, batch_to_run} = Scheduler.tick(state.async_jobs, batch)
    state = %{state | async_jobs: async_jobs}
    if batch_to_run, do: start_sample(state, batch_to_run), else: state
  end

  defp start_sample(state, batch) do
    task = Task.Supervisor.async_nolink(Exdock.Client.Connection.TaskSupervisor, batch.function)
    %{state | samples: Map.put(state.samples, task.ref, %{task: task, batch: batch})}
  end

  defp publish_current_sample(state, batch, result) do
    case Async.get(state.async_jobs, batch.name, batch.id) do
      %Async.Batch{generation: generation} when generation == batch.generation -> publish_sample(state, batch, result)
      _superseded -> :ok
    end
  end

  defp publish_sample(state, batch, {:ok, result}) do
    sample = state.wire.encode_result(Atom.to_string(batch.name), result)
    message = ProtocolMessage.resource_sample(state.node, batch.id, sample)
    GenServer.cast(state.owner, {:client_message, {:resource_sample, message}})
  end

  defp publish_sample(_state, batch, {:error, error}),
    do: Logger.warning("Async.Response [#{batch.name}]: #{inspect(error)}")
end
