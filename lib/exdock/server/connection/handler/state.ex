defmodule Exdock.Server.Connection.Handler.State do
  @moduledoc """
  Mutable connection-handler data and remote-job timer lifecycle.

  The GenServer owns socket I/O and protocol routing; this module owns the shape
  of its state and the bookkeeping transitions for dispatched remote jobs.
  """

  alias Exdock.Protocol.Messages.JobResult
  alias Exdock.Server.Connection.{RemoteJobs, Session, WireMessage}
  alias Exdock.Server.Jobs.Job

  @remote_job_timeout Exdock.Protocol.ExecutionBudget.result_timeout()

  defstruct parent_pid: nil,
            auth_key: nil,
            socket: nil,
            heartbeat_timer: nil,
            connected_at: nil,
            session: nil,
            remote_jobs: nil

  @type t :: %__MODULE__{
          parent_pid: pid(),
          auth_key: String.t(),
          socket: :ssl.sslsocket(),
          heartbeat_timer: reference() | nil,
          connected_at: DateTime.t(),
          session: Session.t(),
          remote_jobs: RemoteJobs.t()
        }

  @spec new(pid(), String.t(), :ssl.sslsocket()) :: t()
  def new(parent_pid, auth_key, socket) do
    %__MODULE__{
      parent_pid: parent_pid,
      auth_key: auth_key,
      socket: socket,
      connected_at: DateTime.utc_now(),
      session: Session.new(),
      remote_jobs: RemoteJobs.new()
    }
  end

  @spec put_session(t(), Session.t()) :: t()
  def put_session(%__MODULE__{} = state, %Session{} = session),
    do: %{state | session: session}

  @spec track_dispatched_job(t(), Job.t()) :: t()
  def track_dispatched_job(
        %__MODULE__{} = state,
        %Job{id: id, name: name} = job
      )
      when is_binary(id) and is_atom(name) do
    job =
      if name == :node_refresh,
        do: %{job | refresh_generation: System.unique_integer([:monotonic, :positive])},
        else: job

    track_job(state, job)
  end

  @doc "Renews only activity matching a job dispatched on this connection."
  @spec renew_dispatched_job(t(), WireMessage.t()) :: {:ok, t()} | {:error, term()}
  def renew_dispatched_job(state, %WireMessage{type: :progress} = message) do
    # Correlation is pure; keep the original entries while validating identity.
    case RemoteJobs.correlate(state.remote_jobs, state.session.client_name, %{message | type: :result}) do
      {:ok, _consumed_copy, _timer, job} -> {:ok, track_job(state, job)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp track_job(state, %Job{id: id} = job) do
    token = make_ref()
    timer = Process.send_after(self(), {:remote_job_timeout, id, token}, @remote_job_timeout)

    {remote_jobs, previous_timer} =
      RemoteJobs.track(state.remote_jobs, job, timer, token)

    if previous_timer, do: Process.cancel_timer(previous_timer)
    put_remote_jobs(state, remote_jobs)
  end

  @spec correlate_wire_result(t(), WireMessage.t()) ::
          {:ok, t(), Job.t()} | {:error, :unknown_job | :job_mismatch | :node_mismatch}
  def correlate_wire_result(%__MODULE__{} = state, %WireMessage{type: :result} = message) do
    case RemoteJobs.correlate(state.remote_jobs, state.session.client_name, message) do
      {:ok, remote_jobs, timer, job} ->
        Process.cancel_timer(timer)
        {:ok, put_remote_jobs(state, remote_jobs), job}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec expire_dispatched_job(t(), String.t(), reference()) ::
          {:ok, t(), JobResult.t()} | {:error, :unknown_job}
  def expire_dispatched_job(%__MODULE__{} = state, job_id, token)
      when is_binary(job_id) and is_reference(token) do
    case RemoteJobs.expire(state.remote_jobs, state.session.client_name, job_id, token) do
      {:ok, remote_jobs, timer, message} ->
        Process.cancel_timer(timer)
        {:ok, put_remote_jobs(state, remote_jobs), message}

      {:error, :unknown_job} ->
        {:error, :unknown_job}
    end
  end

  defp put_remote_jobs(%__MODULE__{} = state, %RemoteJobs{} = remote_jobs),
    do: %{state | remote_jobs: remote_jobs}
end
