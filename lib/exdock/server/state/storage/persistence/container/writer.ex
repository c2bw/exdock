defmodule Exdock.Server.State.Storage.Persistence.Container.Writer do
  @moduledoc false

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.BatchWriter
  alias Exdock.Server.State.Storage.Persistence.ContainerSettings
  alias Exdock.Server.State.Storage.Persistence.Container.Mapper
  alias Exdock.Server.State.Storage.Persistence.TagInfo, as: TagInfoPersistence
  alias Exdock.Domain.Container, as: RuntimeContainer
  alias Exdock.Domain.Container.{Core, Settings}
  alias Exdock.Domain.TagInfo

  @spec same?(RuntimeContainer.t(), RuntimeContainer.t() | nil) :: boolean()
  def same?(%RuntimeContainer{}, nil), do: false

  def same?(%RuntimeContainer{} = left, %RuntimeContainer{} = right) do
    Database.Container.same?(Mapper.database_record(left), Mapper.database_record(right))
  end

  @spec insert(RuntimeContainer.t()) :: :ok | {:error, term()}
  def insert(
        %RuntimeContainer{
          node: node,
          name: name,
          core: %Core{
            settings: %Settings{} = settings,
            image_data: %Core.ImageData{tag_info: tag_info}
          }
        } = container
      ) do
    with :ok <- persist_tag_info(tag_info),
         :ok <- persist_settings(settings, node, name),
         :ok <- persist_container(container) do
      :ok
    end
  end

  @spec insert_many([RuntimeContainer.t()]) :: :ok | {:error, term()}
  def insert_many(containers) when is_list(containers) do
    with :ok <- persist_dependencies(containers),
         :ok <- persist_container_rows(containers) do
      :ok
    end
  end

  @spec sync_node_set(Exdock.NodeId.t(), [String.t()]) :: :ok | {:error, term()}
  def sync_node_set(node, container_names) when is_binary(node) and is_list(container_names) do
    node
    |> Database.Container.mark_set(container_names)
    |> BatchWriter.sync_set(:container_set_sync)
  end

  defp persist_tag_info(%TagInfo{} = tag_info) do
    tag_info
    |> TagInfoPersistence.insert_if_not_exists()
    |> Exdock.Server.State.Storage.Persistence.Result.normalize_insert_result(:tag_info_insert)
  end

  defp persist_settings(%Settings{} = settings, node, name) do
    settings
    |> ContainerSettings.insert(node, name)
    |> Exdock.Server.State.Storage.Persistence.Result.normalize_insert_result(:settings_insert)
  end

  defp persist_dependencies(containers) do
    with :ok <- persist_tag_infos(containers) do
      BatchWriter.persist_each(containers, fn
        %RuntimeContainer{node: node, name: name, core: %Core{settings: %Settings{} = settings}} ->
          persist_settings(settings, node, name)
      end)
    end
  end

  defp persist_tag_infos(containers) do
    containers
    |> Enum.map(fn %RuntimeContainer{
                     core: %Core{image_data: %Core.ImageData{tag_info: tag_info}}
                   } ->
      tag_info
    end)
    |> Enum.uniq_by(&{&1.tag, &1.platform})
    |> BatchWriter.persist_each(&persist_tag_info/1)
  end

  defp persist_container(%RuntimeContainer{} = container) do
    container
    |> Mapper.database_record()
    |> Database.Container.insert()
    |> Exdock.Server.State.Storage.Persistence.Result.normalize_insert_result(:container_insert)
  end

  defp persist_container_rows(containers) do
    BatchWriter.insert_rows(
      containers,
      &Mapper.database_record/1,
      &Database.Container.insert_all/1,
      :container_insert_all
    )
  end
end
