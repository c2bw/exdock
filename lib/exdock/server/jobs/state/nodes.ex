defmodule Exdock.Server.Jobs.State.Nodes do
  @moduledoc """
  Reverse index of node name to remote job ids.

  The dispatcher uses this index when a node disconnects so every job running on
  that node can be failed through the normal result path.
  """

  alias Exdock.Server.Jobs

  defstruct [
    :nodes
  ]

  @empty_job_ids MapSet.new()

  @type t :: %__MODULE__{
          nodes: %{String.t() => MapSet.t(String.t())}
        }

  @spec new() :: t()
  def new(), do: %__MODULE__{nodes: %{}}

  @doc """
  Track a remote job under each node it targets.

  Remote job ownership is a reverse index: node name -> active remote job ids.
  """
  @spec add(t(), Jobs.Job.t()) :: t()
  def add(%__MODULE__{} = state, %Jobs.Job{type: %Jobs.Job.Local{}}), do: state

  # Linked jobs receive their owner's aggregate result, including disconnects.
  def add(%__MODULE__{} = state, %Jobs.Job{status: :linked}), do: state

  def add(%__MODULE__{nodes: nodes} = state, %Jobs.Job{type: %Jobs.Job.Remote{nodes: targets}, id: id}),
    do: %{state | nodes: index_job_by_target_node(nodes, targets, id)}

  @doc """
  Remove a job id from every node index.
  """
  @spec remove(t(), String.t()) :: t()
  def remove(%__MODULE__{nodes: nodes} = state, id),
    do: %{state | nodes: remove_job_from_all_nodes(nodes, id)}

  @doc """
  Return active remote job ids for a node.
  """
  @spec ids(t(), String.t()) :: list(String.t())
  def ids(%__MODULE__{nodes: nodes} = _state, node) when is_binary(node) do
    nodes
    |> Map.get(node_key(node), @empty_job_ids)
    |> MapSet.to_list()
  end

  defp index_job_by_target_node(nodes, targets, job_id) when is_list(targets) and is_binary(job_id) do
    Enum.reduce(targets, nodes, &index_job_under_node(&1, &2, job_id))
  end

  defp index_job_under_node(node, nodes, job_id)
       when is_binary(node) and is_binary(job_id) do
    Map.update(nodes, node_key(node), MapSet.new([job_id]), &MapSet.put(&1, job_id))
  end

  defp remove_job_from_all_nodes(nodes, job_id) do
    nodes
    |> Enum.map(&remove_job_from_node(&1, job_id))
    |> Enum.reject(&empty_node_bucket?/1)
    |> Map.new()
  end

  defp remove_job_from_node({node_key, jobs}, job_id), do: {node_key, MapSet.delete(jobs, job_id)}

  defp empty_node_bucket?({_node_key, jobs}), do: MapSet.size(jobs) == 0

  @spec node_key(String.t()) :: String.t()
  defp node_key(node) when is_binary(node), do: node
end
