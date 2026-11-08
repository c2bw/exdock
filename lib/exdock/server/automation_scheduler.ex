defmodule Exdock.Server.AutomationScheduler do
  @moduledoc """
  Owns automation timer lifecycle independently from authoritative domain state.

  Every scheduled message carries a generation. Messages from cancelled or
  already-delivered timers are ignored after a schedule replacement.
  """

  use GenServer

  alias Exdock.Runtime.Coordinator
  alias Exdock.Server.State.PeriodicJob

  defstruct generation: 0, job: nil, timer: nil

  @type t :: %__MODULE__{
          generation: non_neg_integer(),
          job: PeriodicJob.t(),
          timer: reference() | nil
        }

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec replace(PeriodicJob.t()) :: :ok
  def replace(%PeriodicJob{} = job) do
    if Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, {:replace, job}), else: :ok
  end

  @impl true
  def init(_opts) do
    job = Coordinator.query(:periodic_job)
    {:ok, schedule(%__MODULE__{job: job})}
  end

  @impl true
  def handle_cast({:replace, %PeriodicJob{} = job}, state) do
    state =
      state
      |> cancel_timer()
      |> Map.put(:job, job)
      |> Map.update!(:generation, &(&1 + 1))
      |> schedule()

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:automation_tick, generation},
        %__MODULE__{generation: generation, job: %PeriodicJob{next_run: %DateTime{}} = job} = state
      ) do
    :ok = Coordinator.run_periodic_job()

    {:noreply,
     state
     |> Map.put(:timer, nil)
     |> Map.update!(:generation, &(&1 + 1))
     |> Map.put(:job, PeriodicJob.set_next(job))
     |> schedule()}
  end

  def handle_info({:automation_tick, _stale_generation}, state), do: {:noreply, state}

  defp schedule(%__MODULE__{job: %PeriodicJob{next_run: nil}} = state), do: %{state | timer: nil}

  defp schedule(%__MODULE__{job: %PeriodicJob{next_run: next_run}, generation: generation} = state) do
    delay_ms = max(DateTime.diff(next_run, DateTime.utc_now(), :millisecond), 0)
    %{state | timer: Process.send_after(self(), {:automation_tick, generation}, delay_ms)}
  end

  defp cancel_timer(%__MODULE__{timer: nil} = state), do: state

  defp cancel_timer(%__MODULE__{timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | timer: nil}
  end
end
