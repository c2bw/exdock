defmodule Exdock.Server.State.Storage.Persistence.Container.Mapper do
  @moduledoc "Explicit mapping between durable container records and runtime attributes."

  alias Exdock.Database
  alias Exdock.Domain.Container, as: RuntimeContainer
  alias Exdock.Domain.Container.{Configuration, Core}
  alias Exdock.Domain.Image
  alias Exdock.Domain.TagInfo
  alias Exdock.Server.State.Storage.Persistence.PersistedStruct

  @spec runtime_attributes(Database.Container.Record.t()) :: map()
  def runtime_attributes(%Database.Container.Record{} = record) do
    %{
      node: record.node,
      name: record.name,
      id: record.id,
      is_running: record.is_running,
      stack_name: record.stack_name,
      configuration: PersistedStruct.decode(record.configuration, Configuration),
      state: PersistedStruct.decode(record.state, Core.State),
      image_tag: record.image_tag,
      image_id: record.image_id,
      image_status: record.image_status,
      is_deleted: record.is_deleted
    }
  end

  @spec database_record(RuntimeContainer.t()) :: Database.Container.Record.t()
  def database_record(%RuntimeContainer{
        node: node,
        name: name,
        id: id,
        core: %Core{
          is_deleted: is_deleted,
          stack_name: stack_name,
          configuration: configuration,
          state: state,
          is_running: is_running,
          image_data: %Core.ImageData{
            status: status,
            tag_info: %TagInfo{tag: tag},
            image: %Image{id: image_id}
          }
        }
      }) do
    Database.Container.new(%{
      node: node,
      name: name,
      id: id,
      is_running: is_running,
      stack_name: stack_name,
      configuration: configuration,
      state: state,
      image_tag: tag,
      image_id: image_id,
      image_status: status,
      is_deleted: is_deleted
    })
  end
end
