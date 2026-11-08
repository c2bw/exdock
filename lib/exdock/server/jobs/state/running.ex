defmodule Exdock.Server.Jobs.State.Running do
  @moduledoc """
  Tracks jobs that have been accepted by the dispatcher and not yet cleaned up.

  Jobs have globally unique IDs, so local and remote work share one index.
  Execution-type checks remain explicit for operations that only apply to
  remote jobs, such as per-node completion.
  """

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Job

  defstruct jobs: %{}

  @type t :: %__MODULE__{jobs: %{String.t() => Jobs.Job.t()}}
  @type job_entry :: {String.t(), Jobs.Job.t()}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec get(t(), String.t()) :: Jobs.Job.t() | nil
  def get(%__MODULE__{jobs: jobs}, id) when is_binary(id), do: Map.get(jobs, id)

  @spec ids(t()) :: MapSet.t(String.t())
  def ids(%__MODULE__{jobs: jobs}), do: jobs |> Map.keys() |> MapSet.new()

  @spec get_remote(t(), String.t()) :: Jobs.Job.t() | nil
  def get_remote(%__MODULE__{} = state, id) when is_binary(id) do
    case get(state, id) do
      %Job{type: %Job.Remote{}} = job -> job
      _other -> nil
    end
  end

  @spec get_local(t(), String.t()) :: Jobs.Job.t() | nil
  def get_local(%__MODULE__{} = state, id) when is_binary(id) do
    case get(state, id) do
      %Job{type: %Job.Local{}} = job -> job
      _other -> nil
    end
  end

  @doc """
  Return a running job entry by name, node and parameters.

  This returns the `{id, job}` pair for the first remote job that matches name,
  node set, and parameters, or `nil` if no match is found.

  Checking for local jobs always returns `nil`.
  """
  @spec find_job(t(), Jobs.Job.t()) :: job_entry() | nil
  def find_job(%__MODULE__{}, %Jobs.Job{type: %Jobs.Job.Local{}}), do: nil

  def find_job(
        %__MODULE__{jobs: jobs},
        %Jobs.Job{type: %Jobs.Job.Remote{nodes: nodes}, name: name, parameters: parameters}
      ) do
    Enum.find(jobs, &matching_remote_job?(&1, name, parameters, nodes))
  end

  @doc """
  Return the id of the running job that can satisfy the given job, if any.
  """
  @spec find_job_id(t(), Jobs.Job.t()) :: String.t() | nil
  def find_job_id(%__MODULE__{} = state, %Jobs.Job{} = job) do
    state
    |> find_job(job)
    |> job_entry_id()
  end

  @doc """
  Add a job to the running state.

  Job IDs are the canonical identity. Adding the same ID replaces its previous
  value rather than allowing two bucket-specific versions to diverge.
  """
  @spec add(t(), Jobs.Job.t()) :: t()
  def add(%__MODULE__{jobs: jobs} = state, %Job{id: id} = job) do
    %{state | jobs: Map.put(jobs, id, job)}
  end

  @spec result(t(), Jobs.Result.t()) :: t()
  def result(%__MODULE__{} = state, %Jobs.Result{id: id, node: nil}) do
    state
    |> delete_local(id)
    |> clean()
  end

  def result(%__MODULE__{} = state, %Jobs.Result{id: id, node: node}) do
    state
    |> remove_node(id, node)
    |> clean()
  end

  @doc """
  Remove all jobs that are terminated.
  """
  @spec clean(t()) :: t()
  def clean(%__MODULE__{jobs: jobs} = state) do
    %{state | jobs: Map.reject(jobs, fn {_id, %Job{status: status}} -> status == :terminated end)}
  end

  @doc """
  Remove the node from the list of remaining nodes for a remote job.

  Local jobs, missing IDs, and informational updates with a nil node are left
  unchanged.
  """
  @spec remove_node(t(), String.t(), String.t() | nil) :: t()
  def remove_node(%__MODULE__{} = state, id, nil) when is_binary(id), do: state

  def remove_node(%__MODULE__{} = state, id, node)
      when is_binary(id) and is_binary(node) do
    case get_remote(state, id) do
      nil -> state
      job -> put_job(state, remove_remote_job_node(job, node))
    end
  end

  defp matching_remote_job?({_id, %Job{} = running_job}, name, parameters, nodes),
    do: same_running_remote_work?(running_job, name, parameters, nodes)

  defp job_entry_id({id, %Job{}}), do: id
  defp job_entry_id(nil), do: nil

  defp remove_remote_job_node(%Job{type: %Job.Remote{} = remote} = job, node) do
    remote = Jobs.Job.Remote.remove_node(remote, node)
    job = %{job | type: remote}

    if remote.nodes == [], do: Job.set_status(job, :terminated), else: job
  end

  defp same_running_remote_work?(
         %Job{
           type: %Job.Remote{nodes: running_nodes},
           status: :running,
           name: name,
           parameters: parameters
         },
         name,
         parameters,
         nodes
       ) do
    same_node_set?(nodes, running_nodes)
  end

  defp same_running_remote_work?(%Job{}, _name, _parameters, _nodes), do: false

  defp same_node_set?(left, right), do: MapSet.new(left) == MapSet.new(right)

  defp delete_local(%__MODULE__{} = state, id) do
    case get_local(state, id) do
      nil -> state
      _job -> delete_job(state, id)
    end
  end

  defp put_job(%__MODULE__{jobs: jobs} = state, %Job{id: id} = job),
    do: %{state | jobs: Map.put(jobs, id, job)}

  @doc "Remove a fully completed job from the running index."
  @spec delete_job(t(), String.t()) :: t()
  def delete_job(%__MODULE__{jobs: jobs} = state, id),
    do: %{state | jobs: Map.delete(jobs, id)}
end
