defmodule Exdock.Server.State.Storage.Persistence.AggregateMapperTest do
  use ExUnit.Case, async: true

  alias Exdock.Database
  alias Exdock.Domain.Container, as: RuntimeContainer
  alias Exdock.Domain.Container.{Configuration, Core}
  alias Exdock.Domain.Image, as: RuntimeImage
  alias Exdock.Domain.Image.{Metadata, Settings}
  alias Exdock.Domain.TagInfo
  alias Exdock.Server.State.Storage.Persistence.Container.Mapper, as: ContainerMapper
  alias Exdock.Server.State.Storage.Persistence.Image.Mapper, as: ImageMapper

  test "container mapping names every durable field in both directions" do
    record = %Database.Container.Record{
      node: "node-a",
      name: "app",
      id: "container-id",
      is_running: true,
      stack_name: "stack",
      configuration: %{},
      state: %{},
      image_tag: "ghcr.io/acme/app:latest",
      image_id: "image-id",
      image_status: :updated,
      is_deleted: false
    }

    assert %{
             node: "node-a",
             name: "app",
             configuration: %Configuration{},
             state: %Core.State{}
           } = ContainerMapper.runtime_attributes(record)

    container = %RuntimeContainer{
      node: record.node,
      name: record.name,
      id: record.id,
      core: %Core{
        is_running: record.is_running,
        stack_name: record.stack_name,
        configuration: %Configuration{},
        state: %Core.State{},
        is_deleted: record.is_deleted,
        image_data: %Core.ImageData{
          status: record.image_status,
          tag_info: %TagInfo{tag: record.image_tag},
          image: %RuntimeImage{id: record.image_id}
        }
      }
    }

    assert %Database.Container.Record{
             node: "node-a",
             name: "app",
             image_tag: "ghcr.io/acme/app:latest",
             image_id: "image-id"
           } = ContainerMapper.database_record(container)
  end

  test "image mapping excludes runtime-only fields from the durable record" do
    record = %Database.Image.Record{
      node: "node-a",
      id: "image-id",
      name: "ghcr.io/acme/app:latest",
      tags: ["ghcr.io/acme/app:latest"],
      digest: "sha256:digest",
      size: 100,
      shared_size: 25,
      build_date: ~U[2026-08-01 10:00:00Z]
    }

    metadata = Metadata.default(record.name)
    settings = Settings.default()

    assert %{
             node: "node-a",
             metadata: ^metadata,
             settings: ^settings,
             in_use: true,
             registry_url: registry_url
           } = ImageMapper.runtime_attributes(record, metadata, settings, true)

    assert is_binary(registry_url)

    image = %RuntimeImage{
      node: record.node,
      id: record.id,
      name: record.name,
      tags: record.tags,
      digest: record.digest,
      size: record.size,
      shared_size: record.shared_size,
      build_date: record.build_date,
      metadata: metadata,
      settings: settings
    }

    assert ImageMapper.database_record(image) == record
  end
end
