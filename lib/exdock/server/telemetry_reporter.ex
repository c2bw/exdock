defmodule Exdock.Server.TelemetryReporter do
  use GenServer
  require Logger

  alias Exdock.Server.TelemetryReporter.{MeasurementWindow, MetricExtractor}

  @type measurements_data :: MeasurementWindow.t()

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    server_opts = if is_nil(name), do: [], else: [name: name]
    metrics = required_opt(opts, :metrics)
    wanted_events = required_opt(opts, :wanted_events)

    GenServer.start_link(__MODULE__, {metrics, wanted_events}, server_opts)
  end

  defp required_opt(opts, key) do
    opts[key] || raise ArgumentError, "the :#{key} option is required by #{inspect(__MODULE__)}"
  end

  @impl true
  def init({metrics, wanted_events}) do
    Process.flag(:trap_exit, true)

    # Attach one telemetry callback per requested event and keep only those buckets in state.
    metrics_by_event = selected_metrics_by_event(metrics, wanted_events)
    attach_events(metrics_by_event)

    state = initial_state(metrics_by_event)
    {:ok, state}
  end

  defp selected_metrics_by_event(metrics, wanted_events) do
    metrics
    |> Enum.group_by(& &1.event_name)
    |> Map.take(wanted_events)
  end

  defp attach_events(metrics_by_event) do
    Enum.each(metrics_by_event, &attach_event_metrics/1)
  end

  defp attach_event_metrics({event_name, metrics}) do
    :ok =
      :telemetry.attach(
        attachment_id(event_name),
        event_name,
        &__MODULE__.handle_event/4,
        {metrics, self()}
      )

    Logger.debug("Exdock TelemetryReporter: attached to event #{inspect(event_name)}")
  end

  defp initial_state(metrics_by_event) do
    Map.new(metrics_by_event, fn {event_name, _metrics} ->
      {event_name, MeasurementWindow.new()}
    end)
  end

  @impl true
  def terminate(_, state) do
    detach_events(Map.keys(state))
    :ok
  end

  defp detach_events(event_names) do
    Enum.each(event_names, &:telemetry.detach(attachment_id(&1)))
  end

  defp attachment_id(event_name), do: {__MODULE__, event_name, self()}

  @doc """
    Get the measurement data for the event.
  """
  @spec get_measurement(list(atom()), GenServer.server()) ::
          {:ok, measurements_data()} | {:error, :not_found | :not_started}
  def get_measurement(event_name, server \\ __MODULE__) do
    # Read path used by callers to retrieve the latest aggregated snapshot for an event.
    with_reporter(server, {:error, :not_started}, fn pid ->
      GenServer.call(pid, {:get, event_name})
    end)
  end

  @spec add_measurement(GenServer.server(), list(atom()), any(), list()) :: :ok
  defp add_measurement(server, event_name, raw_measurements, extracted) do
    with_reporter(server, :ok, fn pid ->
      GenServer.cast(pid, {:add, {event_name, raw_measurements, extracted}})
    end)
  end

  defp with_reporter(server, not_running_result, fun) do
    case GenServer.whereis(server) do
      nil ->
        not_running_result

      pid ->
        fun.(pid)
    end
  end

  @impl true
  def handle_cast({:add, {event_name, raw_measurements, extracted_metrics}}, state) do
    state =
      Map.update!(
        state,
        event_name,
        &MeasurementWindow.record(&1, event_name, raw_measurements, extracted_metrics)
      )

    {:noreply, state}
  end

  @impl true
  def handle_call({:get, event_name}, _from, state) do
    {:reply, measurement_lookup(state, event_name), state}
  end

  defp measurement_lookup(state, event_name) do
    case Map.fetch(state, event_name) do
      {:ok, data} ->
        {:ok, data}

      :error ->
        Logger.warning("Exdock TelemetryReporter: no data for event #{inspect(event_name)}")
        {:error, :not_found}
    end
  end

  def handle_event(event_name, measurements, metadata, {metrics, reporter}) do
    case MetricExtractor.extract(metrics, measurements, metadata) do
      [] -> :ok
      extracted -> add_measurement(reporter, event_name, measurements, extracted)
    end

    :ok
  end
end
