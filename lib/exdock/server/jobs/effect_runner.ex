defmodule Exdock.Server.Jobs.EffectRunner do
  @moduledoc """
  Interprets effects emitted by the pure job-state transition layer.

  Process spawning, remote dispatch, PubSub publication, and coordinator
  commands stay here so the `Jobs` GenServer remains a state-owning mailbox.
  """

  require Logger

  alias Exdock.Runtime.Command
  alias Exdock.Runtime.Coordinator
  alias Exdock.Server.Connection
  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Runtime

  @spec transition(Jobs.State.t(), Jobs.State.event(), Runtime.t()) :: Jobs.State.t()
  def transition(%Jobs.State{} = state, event, %Runtime{} = runtime) do
    {state, effects} = Jobs.State.transition(state, event)
    Enum.reduce(effects, state, &execute_effect(&1, &2, runtime))
  end

  @spec process_result(Jobs.State.t(), Jobs.Result.t(), Runtime.t()) :: Jobs.State.t()
  def process_result(%Jobs.State{} = state, %Jobs.Result{} = result, %Runtime{} = runtime),
    do: transition(state, {:result, result}, runtime)

  defp execute_effect({:job_finished, info, result}, %Jobs.State{} = state, runtime) do
    publisher(runtime).job_finished(info, result, publisher_opts(runtime))
    publisher(runtime).terminal_operation(info, state, result, publisher_opts(runtime))
    state
  end

  defp execute_effect({:job_started, %Jobs.Job{} = job}, %Jobs.State{} = state, runtime) do
    publisher(runtime).job_started(job, publisher_opts(runtime))
    state
  end

  defp execute_effect({:job_result, %Jobs.Result{} = result}, %Jobs.State{} = state, runtime) do
    process_result(state, result, runtime)
  end

  defp execute_effect({:start_local, id, function}, %Jobs.State{} = state, runtime)
       when is_binary(id) and (is_function(function, 1) or is_function(function, 2)) do
    owner = self()
    start_token = make_ref()

    # Install the monitor before the function can run or terminate. Otherwise
    # an immediate worker exit is reported as :noproc and loses its cause.
    case Task.Supervisor.start_child(runtime.task_supervisor, fn ->
           receive do
             {:run_local_job, ^start_token} -> execute_local_job(function, id, runtime, owner)
           end
         end) do
      {:ok, worker_pid} ->
        monitor_ref = Process.monitor(worker_pid)
        send(worker_pid, {:run_local_job, start_token})
        Jobs.State.track_local_worker(state, monitor_ref, id)

      {:error, reason} ->
        Logger.error("Unable to start local job #{id}: #{inspect(reason)}")
        send(owner, {:local_job_failure, Jobs.Result.new(id, nil, nil, {:local_job_start_failed, reason})})
        state
    end
  end

  defp execute_effect({:start_remote, node, %Jobs.Job{} = job}, %Jobs.State{} = state, runtime) do
    case Connection.TCPServer.send_command(node, job, runtime.connection) do
      :ok ->
        state

      {:error, reason} ->
        Logger.warning("Remote job #{job.id} could not be dispatched to #{node}: #{inspect(reason)}")
        process_result(state, Jobs.Result.new(job.id, node, nil, :nodedown), runtime)
    end
  end

  defp execute_effect({:demonitor, monitor_ref}, %Jobs.State{} = state, _runtime)
       when is_reference(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    state
  end

  defp execute_effect({:package_result, id, completion_error}, %Jobs.State{} = state, runtime) do
    publisher(runtime).package_finished(id, completion_error, publisher_opts(runtime))
    state
  end

  defp execute_effect({:server_command, %Command.Workflow{} = command}, %Jobs.State{} = state, runtime) do
    Coordinator.command(nil, command, server: runtime.coordinator)
    state
  end

  defp execute_effect({:workflow_stopped, error}, %Jobs.State{} = state, _runtime) do
    Logger.warning("Stopping workflow after failed step: #{inspect(error)}")
    state
  end

  defp execute_local_job(function, id, runtime, owner) do
    try do
      run_local_function(function, id, runtime)
    rescue
      exception ->
        report_local_job_failure(owner, id, :error, exception, __STACKTRACE__)
    catch
      kind, reason ->
        report_local_job_failure(owner, id, kind, reason, __STACKTRACE__)
    end
  end

  defp run_local_function(function, id, runtime) when is_function(function, 2),
    do: function.(id, runtime)

  defp run_local_function(function, id, _runtime) when is_function(function, 1),
    do: function.(id)

  defp report_local_job_failure(owner, id, kind, reason, stacktrace) do
    Logger.error("Local job #{id} failed: #{Exception.format(kind, reason, stacktrace)}")
    send(owner, {:local_job_failure, Jobs.Result.new(id, nil, nil, {:local_job_failed, kind, reason})})
  end

  defp publisher(%Runtime{} = runtime), do: runtime.publisher
  defp publisher_opts(%Runtime{} = runtime), do: Runtime.publisher_opts(runtime)
end
