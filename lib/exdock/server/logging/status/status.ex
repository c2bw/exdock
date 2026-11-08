defmodule Exdock.Server.Logging.Status do
  @moduledoc """
  View-model state for the live status dashboard.

  Each job type delegates custom behavior to its job module, while this module
  owns the shared lifecycle: register jobs, push updates/results, and clean up
  completed work. `Dashboard` owns the derived operator-facing rows.
  """

  alias Exdock.Server.Jobs
  alias Exdock.Server.Logging.Status.{Dashboard, JobAdapter, JobRegistry, Lifecycle, TrackedJob}
  alias Exdock.Server.Logging.Status.Utils
  alias Exdock.Domain.Repository.Release

  defstruct latest_job: "Ready",
            latest_job_message: "no job in queue",
            latest_job_message_is_error: false,
            errors: [],
            dash: %{},
            jobs: %{}

  @requested_job_state {:ok, :requested}

  @type job_state :: TrackedJob.state()
  @type job_name :: JobRegistry.job_name()

  @type t :: %__MODULE__{
          latest_job: String.t(),
          latest_job_message: String.t(),
          latest_job_message_is_error: boolean(),
          errors: list(),
          dash: Dashboard.t(),
          jobs: %{{job_name(), String.t()} => TrackedJob.t()}
        }

  @type log_update :: {String.t(), :finished | :errored, keyword()} | nil
  @type effect :: {:notify_repository_release, Release.t()}

  @spec new() :: t()
  def new, do: %__MODULE__{dash: Dashboard.new()}

  @doc """
  Return the log message for the module given the data.
  """
  @spec log(atom(), Jobs.Payload.job_data()) :: {Jobs.Payload.message(), keyword()} | false
  def log(job_name, data) do
    job_name |> JobRegistry.fetch!() |> JobAdapter.log(data)
  end

  # Lifecycle

  @spec start(t(), Lifecycle.t()) :: t()
  def start(%__MODULE__{} = status, %Lifecycle{phase: :started} = lifecycle) do
    adapter = JobRegistry.fetch!(lifecycle.job_name)

    status
    |> put_job(adapter, lifecycle, @requested_job_state)
    |> JobAdapter.add(adapter, lifecycle)
    |> add_dashboard_rows(lifecycle, @requested_job_state)
  end

  @doc false
  @spec update_transition(t(), Lifecycle.t()) :: {t(), log_update(), [effect()]}
  def update_transition(%__MODULE__{} = status, %Lifecycle{phase: :updated} = lifecycle) do
    case current_job_data(status, lifecycle) do
      nil ->
        {status, nil, []}

      _job_data ->
        adapter = JobRegistry.fetch!(lifecycle.job_name)

        # Any update error is reflected in the live log as soon as it happens.
        updated_status =
          status
          |> JobAdapter.update(adapter, lifecycle)
          # Some modules normalize their data inside their update hooks, so the row key
          # is looked up with the incoming payload and then rewritten using stored data.
          |> refresh_dashboard_row(lifecycle)

        effects = JobRegistry.update_effects(updated_status, lifecycle)
        {updated_status, update_error_log(lifecycle.job_id, lifecycle.error), effects}
    end
  end

  @doc false
  @spec result_transition(t(), Lifecycle.t()) :: {t(), log_update(), [effect()]}
  def result_transition(%__MODULE__{} = status, %Lifecycle{phase: :finished} = lifecycle) do
    case current_job_data(status, lifecycle) do
      nil ->
        {status, nil, []}

      job_data ->
        result_data = result_data(lifecycle.data, lifecycle.error, job_data.data)
        lifecycle = %{lifecycle | data: result_data}
        log_update = result_log_update(status, lifecycle)
        effects = JobRegistry.result_effects(status, lifecycle)
        {finalize_job(status, lifecycle), log_update, effects}
    end
  end

  defp current_job_data(status, %Lifecycle{job_name: job_name, job_id: job_id}),
    do: current_job_data(status, job_name, job_id)

  defp current_job_data(status, job_name, job_id), do: Utils.get_job_data(status, job_name, job_id)

  defp put_job(status, adapter, %Lifecycle{} = lifecycle, state) do
    normalized_data = JobAdapter.data_init(adapter, lifecycle.data)

    tracked_job = TrackedJob.new(lifecycle.locations, normalized_data, state)
    Utils.set_job_data(status, lifecycle.job_name, lifecycle.job_id, tracked_job)
  end

  defp update_error_log(_job_id, nil), do: nil
  defp update_error_log(job_id, _error), do: {job_id, :errored, []}

  defp result_data(nil, error, tracked_data) when not is_nil(error), do: tracked_data
  defp result_data(data, _error, _tracked_data), do: data

  defp result_log_update(status, %Lifecycle{} = lifecycle) do
    result = if is_nil(lifecycle.error), do: :finished, else: :errored

    options =
      if is_nil(lifecycle.error),
        do: JobRegistry.completion_log_options(status, lifecycle),
        else: [lazy: true]

    {lifecycle.job_id, result, options}
  end

  defp finalize_job(status, %Lifecycle{} = lifecycle) do
    job_data = current_job_data(status, lifecycle)
    adapter = JobRegistry.fetch!(lifecycle.job_name)

    status
    |> JobAdapter.result(adapter, lifecycle)
    |> finalize_dashboard_row(lifecycle, job_data.data)
    |> Utils.remove_job(lifecycle.job_name, lifecycle.job_id)
  end

  defp add_dashboard_rows(status, %Lifecycle{} = lifecycle, state) do
    job_data = current_job_data(status, lifecycle)

    %{
      status
      | dash: Dashboard.add(status.dash, lifecycle, state, job_data.data)
    }
  end

  defp refresh_dashboard_row(status, %Lifecycle{} = lifecycle) do
    job_data = current_job_data(status, lifecycle)

    %{status | dash: Dashboard.refresh(status.dash, lifecycle, job_data.data)}
  end

  defp finalize_dashboard_row(status, %Lifecycle{} = lifecycle, tracked_data) do
    %{
      status
      | dash: Dashboard.finalize(status.dash, lifecycle, tracked_data)
    }
  end

  # Messages

  @doc """
  Attach a human-readable progress message to a job.
  """
  @spec update_job_message(t(), atom(), String.t(), Lifecycle.location() | nil, any()) :: t()
  def update_job_message(%__MODULE__{} = status, job_name, job_id, node, message) do
    status = Utils.set_job_data_message(status, job_name, job_id, message)
    data = tracked_job_data_payload(status, job_name, job_id)

    %{
      status
      | dash: Dashboard.put_message(status.dash, job_name, job_id, node, data, message)
    }
  end

  defp tracked_job_data_payload(status, job_name, job_id) do
    case current_job_data(status, job_name, job_id) do
      nil -> nil
      job_data -> job_data.data
    end
  end

  # Error helpers

  @doc """
  Returns true if any dash entry has an error or warning requiring attention.
  """
  @spec has_errors?(t()) :: boolean()
  def has_errors?(%__MODULE__{} = status), do: Dashboard.errors?(status.dash)

  @doc """
  Remove error and warning dash entries while leaving active/requested entries intact.
  """
  @spec clear_errors(t()) :: t()
  def clear_errors(%__MODULE__{} = status) do
    # Clearing errors is UI cleanup only. In-flight requested entries stay
    # visible so operators can keep watching active jobs.
    %{status | dash: Dashboard.clear_errors(status.dash)}
  end

  @spec count_active_jobs(t()) :: non_neg_integer()
  def count_active_jobs(%__MODULE__{} = status) do
    # This counts tracked lifecycle entries, not dashboard rows.
    # A multi-node job can render multiple rows while representing one job.
    status.jobs |> Enum.count()
  end
end
