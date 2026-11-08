defmodule Exdock.Server.JobsCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.{Detail, Spec}

  @jobs_key {__MODULE__, :jobs}
  @supervisor_key {__MODULE__, :supervisor}

  using do
    quote do
      import Exdock.Server.JobsCase
    end
  end

  setup do
    if Process.whereis(Exdock.PubSub) == nil do
      start_supervised!({Phoenix.PubSub, name: Exdock.PubSub})
    end

    owner = self()
    jobs = {:global, {Jobs, owner}}
    supervisor = {:global, {Jobs.Supervisor, owner}}
    task_supervisor = {:global, {Jobs.TaskSupervisor, owner}}

    Process.put(@jobs_key, jobs)
    Process.put(@supervisor_key, supervisor)

    start_supervised!({Jobs.Supervisor, supervisor_name: supervisor, task_supervisor: task_supervisor, name: jobs})

    Jobs.subscribe()
    {:ok, jobs: jobs, jobs_supervisor: supervisor}
  end

  def jobs_server, do: fetch_process_value!(@jobs_key)
  def jobs_supervisor, do: fetch_process_value!(@supervisor_key)

  def run_blocking_local_detail(name, server \\ jobs_server()) do
    detail = blocking_local_detail(name)
    Jobs.add(detail, server)
    detail
  end

  def blocking_local_detail(name) do
    owner = self()

    spec =
      Spec.new(
        Spec.Local.new(fn id ->
          send(owner, {:blocking_local_job_started, self(), id})

          receive do
            {:finish_local_job, ^id} -> :ok
          after
            5_000 -> :ok
          end
        end),
        [],
        nil
      )

    Detail.new(name, spec)
  end

  def remote_detail(name, node) do
    spec = Spec.new(Spec.Remote.new(node), [], nil)
    Detail.new(name, spec)
  end

  def get_started_task_pid do
    receive do
      {:blocking_local_job_started, pid, _id} -> pid
    after
      1_000 -> ExUnit.Assertions.flunk("Expected blocking local job to start")
    end
  end

  defp fetch_process_value!(key) do
    Process.get(key) || raise "JobsCase process value is unavailable: #{inspect(key)}"
  end
end
