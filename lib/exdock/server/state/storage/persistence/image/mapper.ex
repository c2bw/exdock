defmodule Exdock.Server.State.Storage.Persistence.Image.Mapper do
  @moduledoc "Explicit mapping between durable image records and runtime attributes."

  alias Exdock.Database
  alias Exdock.Domain.Image, as: RuntimeImage
  alias Exdock.Domain.Image.{Metadata, Settings}
  alias Exdock.ImageReference

  @spec runtime_attributes(Database.Image.Record.t(), Metadata.t(), Settings.t(), boolean()) :: map()
  def runtime_attributes(
        %Database.Image.Record{} = record,
        %Metadata{} = metadata,
        %Settings{} = settings,
        in_use
      )
      when is_boolean(in_use) do
    %{
      node: record.node,
      id: record.id,
      name: record.name,
      tags: record.tags,
      digest: record.digest,
      repo_digests: record.repo_digests,
      size: record.size,
      shared_size: record.shared_size,
      build_date: record.build_date,
      metadata: metadata,
      registry_url: ImageReference.registry_url(record.name),
      in_use: in_use,
      settings: settings
    }
  end

  @spec database_record(RuntimeImage.t()) :: Database.Image.Record.t()
  def database_record(%RuntimeImage{} = image) do
    Database.Image.new(%{
      node: image.node,
      id: image.id,
      name: image.name,
      tags: image.tags,
      digest: image.digest,
      repo_digests: image.repo_digests,
      size: image.size,
      shared_size: image.shared_size,
      build_date: image.build_date
    })
  end
end
