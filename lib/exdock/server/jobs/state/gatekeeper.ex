defmodule Exdock.Server.Jobs.State.Gatekeeper do
  @moduledoc """
  Prevents duplicate mutating jobs from running at the same time.

  Certain Docker operations should not be started twice for the same target
  while an equivalent job is already running. In that case the new job is marked
  linked and will receive the original job's result instead of executing again.
  """

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Catalog
  alias Exdock.Server.Jobs.State.Running

  @container_mutations [:container_start, :container_stop, :container_restart, :container_recreate]

  @doc """
  Mark a job as linked when equivalent remote mutating work is already running.

  The gatekeeper only decides whether this job should execute. `State` records
  which running job owns the equivalent work so terminal results can be fanned
  out later.
  """
  @spec job(Running.t(), Jobs.Job.t()) :: Jobs.Job.t()
  def job(%Running{} = running, %Jobs.Job{} = job) do
    if duplicate_remote_mutation?(running, job), do: Jobs.Job.set_linked(job), else: job
  end

  defp duplicate_remote_mutation?(%Running{} = running, %Jobs.Job{} = job) do
    linkable_remote_mutation?(job) and equivalent_remote_job_running?(running, job) and
      not conflicting_container_work?(running, job)
  end

  # A stop -> start -> stop sequence must reach the agent in full. Linking the
  # last stop to the first would discard the user's final requested state.
  defp conflicting_container_work?(
         %Running{jobs: jobs},
         %Jobs.Job{
           name: name,
           parameters: [target | _],
           type: %Jobs.Job.Remote{nodes: nodes}
         } = job
       )
       when name in @container_mutations do
    Enum.any?(jobs, fn
      {_,
       %Jobs.Job{status: :running, name: other_name, parameters: [^target | _], type: %Jobs.Job.Remote{nodes: other_nodes}} =
           other}
      when other_name in @container_mutations ->
        (other.name != job.name or other.parameters != job.parameters) and
          not MapSet.disjoint?(MapSet.new(nodes), MapSet.new(other_nodes))

      _ ->
        false
    end)
  end

  defp conflicting_container_work?(_running, _job), do: false

  defp linkable_remote_mutation?(%Jobs.Job{type: %Jobs.Job.Remote{}, name: name}),
    do: Catalog.linkable_remote_mutation?(name)

  defp linkable_remote_mutation?(%Jobs.Job{}), do: false

  defp equivalent_remote_job_running?(%Running{} = running, %Jobs.Job{} = job) do
    Running.find_job(running, job) != nil
  end
end
