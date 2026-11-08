defmodule Exdock.ReadModel.NodePage do
  @moduledoc """
  Node-scoped assigns for the container detail page.

  Initial snapshots and cluster broadcasts both pass through this module so the
  LiveView does not need to understand cluster-wide projection payloads.
  """

  alias Exdock.ReadModel.{ClusterNode, Node, Projections}
  alias Exdock.Runtime.Projection

  @type update :: {:ok, map()} | :unchanged | :missing | :unhandled

  @spec initial(String.t(), %{String.t() => ClusterNode.t()}, Node.t()) ::
          {:ok, map()} | :missing
  def initial(nodename, nodes, %Node{} = detail)
      when is_binary(nodename) and is_map(nodes) do
    case Map.fetch(nodes, nodename) do
      {:ok, node} ->
        {:ok,
         %{
           nodename: nodename,
           node: node,
           node_last_fetch: node.fetched_at,
           containers_core: detail.containers_core,
           containers_extended: detail.containers_extended,
           node_info: detail.info
         }}

      :error ->
        :missing
    end
  end

  @spec broadcast_assigns(atom(), term(), String.t()) :: update()
  def broadcast_assigns(:nodes, payload, nodename) when is_binary(nodename) do
    {:ok, %{nodes: nodes, nodes_list: nodes_list}} =
      Projections.broadcast_assigns(:nodes, payload)

    case Map.fetch(nodes, nodename) do
      {:ok, node} ->
        {:ok, %{node: node, node_last_fetch: node.fetched_at, nodes_list: nodes_list}}

      :error ->
        :missing
    end
  end

  def broadcast_assigns(:containers, payload, nodename) when is_binary(nodename) do
    {:ok, %{containers: containers, containers_extended: extended}} =
      Projections.broadcast_assigns(:containers, payload)

    case Map.fetch(containers, nodename) do
      {:ok, node_containers} ->
        {:ok,
         %{
           containers_core: Projection.containers_core(node_containers),
           containers_extended: Map.get(extended, nodename, %{})
         }}

      :error ->
        :unchanged
    end
  end

  def broadcast_assigns(:cluster_info, cluster_info, nodename) when is_binary(nodename) do
    case Map.fetch(cluster_info.by_node_string, nodename) do
      {:ok, info} -> {:ok, %{node_info: info}}
      :error -> :unchanged
    end
  end

  def broadcast_assigns(_source, _payload, _nodename), do: :unhandled
end
