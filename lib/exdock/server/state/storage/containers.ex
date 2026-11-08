defmodule Exdock.Server.State.Storage.Containers do
  @moduledoc """
  Collection facade for Docker containers grouped by node.

  Snapshot construction and configuration reloading live in focused modules;
  this facade owns only lookup and replacement operations over `NodeStorage`.
  """

  alias Exdock.Protocol.Snapshot, as: Client
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster.Utils.NodeStorage

  alias Exdock.Server.State.Storage.Containers.{
    ConfigurationReloader,
    SnapshotBuilder
  }

  alias Exdock.Domain
  alias Exdock.Domain.Container

  @spec reload_configuration(NodeStorage.t(), Storage.TagsInfo.t(), boolean()) ::
          NodeStorage.t()
  def reload_configuration(
        %NodeStorage{} = storage,
        %Storage.TagsInfo{} = tags,
        reload_settings?
      ) do
    ConfigurationReloader.reload(storage, tags, reload_settings?)
  end

  @spec make(
          NodeStorage.t(),
          String.t(),
          [Client.Container.t()],
          Storage.TagsInfo.t()
        ) :: NodeStorage.t()
  def make(
        %NodeStorage{} = storage,
        node,
        containers,
        %Storage.TagsInfo{} = tags
      ) do
    SnapshotBuilder.make(storage, node, containers, tags)
  end

  @spec list(NodeStorage.t()) :: [Domain.Container.t()]
  def list(%NodeStorage{} = storage), do: NodeStorage.all_containers(storage)

  @spec list_node(NodeStorage.t(), String.t()) :: [Domain.Container.t()]
  def list_node(%NodeStorage{} = storage, node) when is_binary(node),
    do: NodeStorage.get_containers(storage, node)

  @spec string_map(NodeStorage.t()) ::
          %{String.t() => [Domain.Container.t()]}
  def string_map(%NodeStorage{} = storage),
    do: NodeStorage.containers_map(storage)

  @spec full_string_map(map()) ::
          %{String.t() => [Domain.Container.t()]}
  def full_string_map(%{cluster: %{storage: %NodeStorage{} = storage}}),
    do: NodeStorage.containers_map(storage)

  @spec set_container(
          NodeStorage.t(),
          String.t(),
          Domain.Container.t()
        ) :: NodeStorage.t()
  def set_container(
        %NodeStorage{} = storage,
        node,
        %Container{name: target_name} = replacement
      ) do
    containers =
      storage
      |> list_node(node)
      |> Enum.map(&replace_by_name(&1, target_name, replacement))

    set_node(storage, node, containers)
  end

  @spec get_container(
          NodeStorage.t(),
          String.t(),
          String.t(),
          :name | :id
        ) :: Domain.Container.t() | nil
  def get_container(%NodeStorage{} = storage, node, identifier, identifier_type)
      when is_binary(node) and is_binary(identifier) and
             identifier_type in [:name, :id] do
    storage
    |> list_node(node)
    |> find_container(identifier, identifier_type)
  end

  @spec set_node(
          NodeStorage.t(),
          String.t(),
          [Domain.Container.t()]
        ) :: NodeStorage.t()
  def set_node(%NodeStorage{} = storage, node, containers)
      when is_binary(node) and is_list(containers) do
    NodeStorage.put_containers(storage, node, containers)
  end

  @spec update_runtime_data(
          NodeStorage.t(),
          String.t(),
          String.t(),
          (Container.t() -> Container.t())
        ) :: NodeStorage.t()
  def update_runtime_data(
        %NodeStorage{} = storage,
        node,
        id,
        update_fn
      )
      when is_binary(node) and is_binary(id) and is_function(update_fn, 1) do
    case get_container(storage, node, id, :id) do
      nil -> storage
      container -> set_container(storage, node, update_fn.(container))
    end
  end

  defp replace_by_name(
         %Container{name: name},
         name,
         %Container{} = replacement
       ),
       do: replacement

  defp replace_by_name(%Container{} = existing, _target, %Container{}),
    do: existing

  defp find_container(containers, identifier, :name),
    do: Enum.find(containers, &match?(%Container{name: ^identifier}, &1))

  defp find_container(containers, identifier, :id),
    do: Enum.find(containers, &match?(%Container{id: ^identifier}, &1))
end
