defmodule Exdock.Server.Jobs.Spec.Remote do
  @moduledoc """
  Remote jobs are executed by one or more connected client nodes.
  """

  defstruct [:nodes]
  @type t :: %__MODULE__{nodes: list(String.t())}

  @spec new(String.t() | [String.t()]) :: t()
  def new(node) when is_binary(node), do: %__MODULE__{nodes: [node]}

  def new(nodes) when is_list(nodes) do
    if Enum.all?(nodes, &is_binary/1) do
      %__MODULE__{nodes: nodes}
    else
      raise ArgumentError, "nodes must be strings"
    end
  end
end
