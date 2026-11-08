defmodule Exdock.Server.Connection.RemoteJobs do
  @moduledoc """
  Pure remote-job correlation state for one authenticated connection.

  Connection phase and handshake data live in `Session`; this module owns only
  dispatched job identities, timeout tokens, and result correlation.
  """

  alias Exdock.Protocol.Messages.JobResult
  alias Exdock.Server.Connection.{DispatchedJobs, WireMessage}
  alias Exdock.Server.Jobs.Job

  @enforce_keys [:entries]
  defstruct entries: %{}

  @type t :: %__MODULE__{entries: DispatchedJobs.t()}

  @spec new() :: t()
  def new, do: %__MODULE__{entries: DispatchedJobs.new()}

  @spec track(t(), Job.t(), reference(), reference()) :: {t(), reference() | nil}
  def track(%__MODULE__{entries: entries} = jobs, %Job{} = job, timer, token) do
    {entries, previous_timer} = DispatchedJobs.track(entries, job, timer, token)
    {%{jobs | entries: entries}, previous_timer}
  end

  @spec correlate(t(), Exdock.NodeId.t(), WireMessage.t()) ::
          {:ok, t(), reference(), Job.t()}
          | {:error, DispatchedJobs.correlation_error() | :job_mismatch}
  def correlate(%__MODULE__{entries: entries} = jobs, client_name, %WireMessage{} = message)
      when is_binary(client_name) do
    case DispatchedJobs.correlate(entries, client_name, message) do
      {:ok, entries, timer, job} -> {:ok, %{jobs | entries: entries}, timer, job}
      {:error, reason} -> {:error, reason}
    end
  end

  def correlate(%__MODULE__{}, _client_name, %WireMessage{}),
    do: {:error, :job_mismatch}

  @spec expire(t(), Exdock.NodeId.t(), String.t(), reference()) ::
          {:ok, t(), reference(), JobResult.t()} | {:error, :unknown_job}
  def expire(%__MODULE__{entries: entries} = jobs, client_name, job_id, token)
      when is_binary(client_name) and is_binary(job_id) and is_reference(token) do
    case DispatchedJobs.expire(entries, client_name, job_id, token) do
      {:ok, entries, timer, message} ->
        {:ok, %{jobs | entries: entries}, timer, message}

      {:error, :unknown_job} ->
        {:error, :unknown_job}
    end
  end
end
