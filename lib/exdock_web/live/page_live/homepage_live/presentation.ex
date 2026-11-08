defmodule ExdockWeb.HomepageLive.Presentation do
  @moduledoc """
  Builds projection-driven homepage rows.

  The page clock changes every few seconds. Keeping sorted nodes and resource
  aggregation in assigns avoids rebuilding stable presentation data on those
  clock-only renders.
  """

  alias ExdockWeb.Commons.NodeSummary.ResourceSummary

  @type t :: %__MODULE__{node_rows: [{String.t(), map()}], resource_rows: map()}

  defstruct node_rows: [], resource_rows: %{}

  @spec build(map(), map()) :: t()
  def build(cluster_info, containers_by_node) do
    %__MODULE__{
      node_rows: node_rows(cluster_info),
      resource_rows: resource_rows(containers_by_node)
    }
  end

  @spec with_cluster_info(t(), map()) :: t()
  def with_cluster_info(%__MODULE__{} = presentation, cluster_info) do
    %{presentation | node_rows: node_rows(cluster_info)}
  end

  @spec with_containers(t(), map()) :: t()
  def with_containers(%__MODULE__{} = presentation, containers_by_node) do
    %{presentation | resource_rows: resource_rows(containers_by_node)}
  end

  defp node_rows(%{by_node_string: nodes}) when is_map(nodes), do: Enum.sort(nodes)
  defp node_rows(_cluster_info), do: []

  defp resource_rows(containers_by_node) when is_map(containers_by_node) do
    Map.new(containers_by_node, fn {node, containers} ->
      {node, ResourceSummary.rows(containers)}
    end)
  end

  defp resource_rows(_containers_by_node), do: %{}
end
