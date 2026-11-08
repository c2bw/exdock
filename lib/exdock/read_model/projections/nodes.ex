defmodule Exdock.ReadModel.Projections.Nodes do
  @moduledoc false

  @behaviour Exdock.ReadModel.Projection

  alias Exdock.Runtime.Projection

  @impl true
  def from_query(%{nodes: nodes, nodes_list: nodes_list}), do: project(nodes, nodes_list)

  @impl true
  def from_broadcast(nodes) do
    nodes = Projection.nodes(nodes)
    %{nodes: nodes, nodes_list: nodes |> Map.keys() |> Enum.sort()}
  end

  defp project(nodes, nodes_list), do: %{nodes: Projection.nodes(nodes), nodes_list: nodes_list}
end
