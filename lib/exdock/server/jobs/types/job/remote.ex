defmodule Exdock.Server.Jobs.Job.Remote do
  @moduledoc """
  Runtime target set for a remote job.
  """

  defstruct [:nodes]
  @type t :: %__MODULE__{nodes: list(String.t())}

  @spec new(list(String.t())) :: t()
  def new(nodes) when is_list(nodes) do
    %__MODULE__{
      nodes: nodes
    }
  end

  @spec remove_node(t(), String.t()) :: t()
  def remove_node(%__MODULE__{nodes: nodes} = job, node) when is_binary(node) do
    nodes = List.delete(nodes, node)
    # Completion state is resolved by the running-job tracker; this helper only
    # removes the node that has reported progress or completion.
    %{job | nodes: nodes}
  end
end
