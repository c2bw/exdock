defmodule Exdock.Runtime.Projection do
  @moduledoc """
  Pure builders for public read-model and broadcast projections.

  Runtime state keeps durable string node identifiers. Projection builders
  validate that invariant at the public read boundary.
  """

  alias Exdock.ReadModel.{ClusterNode, Container, Image, Node, Repository, Value}
  alias Exdock.Server.State.Storage.Cluster.NodeData

  @spec node_map!(map()) :: map()
  def node_map!(data) when is_map(data) do
    Enum.each(data, fn
      {node, _value} when is_binary(node) -> :ok
      {node, _value} -> raise ArgumentError, "non-canonical node key: #{inspect(node)}"
    end)

    data
  end

  @spec nodes(map()) :: %{String.t() => ClusterNode.t()}
  def nodes(data) when is_map(data) do
    project_node_values(data, &ClusterNode.from_domain/1)
  end

  @spec images(map()) :: %{String.t() => [Image.t()]}
  def images(data) when is_map(data) do
    project_node_values(data, fn images -> Enum.map(images, &Image.from_domain/1) end)
  end

  @spec containers(map()) :: %{String.t() => [Container.t()]}
  def containers(data) when is_map(data) do
    project_node_values(data, fn containers -> Enum.map(containers, &Container.from_domain/1) end)
  end

  @spec node(NodeData.t()) :: Node.t()
  def node(%NodeData{} = data) do
    containers = Enum.map(data.containers, &Container.from_domain/1)

    %Node{
      node: to_string(data.node),
      info: Value.project(data.info),
      containers_core: containers_core(containers),
      containers_extended: container_list_extended(containers),
      images: Enum.map(data.images, &Image.from_domain/1)
    }
  end

  @spec containers_core([Container.t() | map()]) :: map()
  def containers_core(containers) when is_list(containers) do
    Map.new(containers, fn container ->
      %Container{core: core} = projected = Container.from_domain(container)
      {Container.key(projected), core}
    end)
  end

  @spec container_list_extended([Container.t() | map()]) :: map()
  def container_list_extended(containers) when is_list(containers) do
    Map.new(containers, fn container ->
      %Container{extended: extended} = projected = Container.from_domain(container)
      {Container.key(projected), extended}
    end)
  end

  @spec containers_extended(map()) :: map()
  def containers_extended(containers) when is_map(containers) do
    containers
    |> node_map!()
    |> Map.new(fn {node, node_containers} ->
      extended =
        Map.new(node_containers, fn container ->
          %Container{extended: extended} = projected = Container.from_domain(container)
          {Container.key(projected), extended}
        end)

      {node, extended}
    end)
  end

  @spec repositories([Exdock.Domain.Repository.t()]) :: [Repository.t()]
  def repositories(repositories) when is_list(repositories) do
    Enum.map(repositories, &Repository.from_domain/1)
  end

  defp project_node_values(data, projector) when is_function(projector, 1) do
    data
    |> node_map!()
    |> Map.new(fn {node, value} -> {node, projector.(value)} end)
  end
end
