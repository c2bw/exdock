defmodule Exdock.Server.Logging.Status.Utils do
  @moduledoc """
  Small helpers for manipulating status dashboard state.

  These helpers keep nested status updates centralized so individual job status
  modules can focus on job-specific data changes.
  """

  alias Exdock.Server.Logging.Status
  alias Exdock.Server.Logging.Status.TrackedJob

  @spec add_entry_to_errors_log(Status.t(), String.t(), DateTime.t()) :: Status.t()
  def add_entry_to_errors_log(status, entry, %DateTime{} = occurred_at) do
    log_message = {log_time(occurred_at), entry}
    %{status | errors: [log_message | status.errors]}
  end

  @doc """
    Update the headline job/message shown above the dashboard.
  """
  @spec set_job_message(Status.t(), String.t(), String.t(), boolean()) :: Status.t()
  def set_job_message(status, job, job_message, is_error \\ false) do
    %{status | latest_job: job, latest_job_message: job_message, latest_job_message_is_error: is_error}
  end

  @doc """
   Store internal status data for a running job.
  """
  @spec set_job_data(Status.t(), atom(), String.t(), TrackedJob.t()) :: Status.t()
  def set_job_data(status, job_name, job_id, %TrackedJob{} = job) do
    %{status | jobs: Map.put(status.jobs, job_key(job_name, job_id), job)}
  end

  @doc """
    Returns the job data for a given job.
  """
  @spec get_job_data(Status.t(), atom(), String.t()) :: TrackedJob.t() | nil
  def get_job_data(status, job_name, job_id) do
    Map.get(status.jobs, job_key(job_name, job_id))
  end

  @doc """
    Remove internal status data for a completed job.
  """
  @spec remove_job(Status.t(), atom(), String.t()) :: Status.t()
  def remove_job(status, job_name, job_id) do
    %{status | jobs: Map.delete(status.jobs, job_key(job_name, job_id))}
  end

  @doc """
    Return the dash entry map for a job type.
  """
  @spec get_dash_entry(Status.t(), atom()) :: any()
  def get_dash_entry(status, job_name, default \\ %{}) do
    Map.get(status, :dash)
    |> Map.get(job_name, default)
  end

  @doc """
    Replace the dash entry map for a job type.
  """
  @spec set_dash_entry(Status.t(), atom(), any()) :: Status.t()
  def set_dash_entry(status, job_name, value) do
    %{status | dash: Map.put(status.dash, job_name, value)}
  end

  @doc """
   Store a progress message in a running job's internal data.
  """
  @spec set_job_data_message(Status.t(), atom(), String.t(), any()) :: Status.t()
  def set_job_data_message(status, job_name, job_id, msg) do
    case get_job_data(status, job_name, job_id) do
      nil -> status
      job_data -> set_job_data(status, job_name, job_id, TrackedJob.put_message(job_data, msg))
    end
  end

  @doc """
    Return the current UTC time in the compact log timestamp format.
  """
  @spec log_time(DateTime.t()) :: String.t()
  def log_time(%DateTime{} = occurred_at) do
    occurred_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()
  end

  @spec split_job_id(String.t() | nil) :: {String.t() | nil, String.t() | nil}
  def split_job_id(nil), do: {nil, nil}

  def split_job_id(job_id) when is_binary(job_id) do
    # Job ids can be nil, a parent id, or a dotted sub-job id generated from a
    # parent id plus a sub-id.
    parent_job_id = strip_sub_job_from_id(job_id)

    sub_job_id = if subjob?(job_id, parent_job_id), do: job_id, else: nil

    {parent_job_id, sub_job_id}
  end

  defp job_key(job_name, job_id), do: {job_name, job_id}

  defp subjob?(job_id, parent_job_id), do: not String.equivalent?(job_id, parent_job_id)

  @doc """
    Strip a dotted sub-job id down to its parent job id.
  """
  @spec strip_sub_job_from_id(String.t()) :: String.t()
  def strip_sub_job_from_id(job_id) do
    job_id
    |> String.split(".")
    |> Enum.at(0)
  end

  @doc """
    Return true if the job id is a dotted sub-job id.
  """
  @spec subjob?(String.t()) :: boolean()
  def subjob?(job_id) do
    not String.equivalent?(job_id, strip_sub_job_from_id(job_id))
  end
end
