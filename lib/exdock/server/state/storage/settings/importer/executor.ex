defmodule Exdock.Server.State.Storage.Settings.Importer.Executor do
  @moduledoc false

  alias Exdock.Server.State.Storage.Persistence.ContainerSettings
  alias Exdock.Server.State.Storage.Persistence.ImageMetadata
  alias Exdock.Server.State.Storage.Persistence.ImageSettings
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Server.State.Storage.Persistence.UserSettings, as: UserSettingsPersistence
  alias Exdock.Server.State.Storage.Persistence.{BatchWriter, Result, Transaction}
  alias Exdock.Server.State.Storage.Settings.Importer.Plan
  alias Exdock.Domain

  @spec execute(Plan.t()) :: :ok | {:error, term()}
  def execute(%Plan{sections: sections}) do
    Transaction.run_each(sections, fn {field, data} ->
      case execute_section(field, data) do
        :ok -> :ok
        {:error, reason} -> {:error, {field, reason}}
      end
    end)
  end

  defp execute_section(:user_settings, settings) do
    settings
    |> UserSettingsPersistence.import(Domain.UserSettings.default_user())
    |> Result.normalize_write_result(:user_settings_import)
  end

  defp execute_section(:nodes_settings, entries) do
    replace_group(
      NodePersistence.purge(),
      entries,
      :node_settings_purge,
      :node_settings_import,
      fn {node, settings} -> NodePersistence.import_settings(settings, node) end
    )
  end

  defp execute_section(:repository_overrides, entries) do
    replace_group(
      ImageMetadata.purge(),
      entries,
      :image_metadata_purge,
      :image_metadata_import,
      fn {image_identifier, metadata} -> ImageMetadata.import(metadata, image_identifier) end
    )
  end

  defp execute_section(:containers_settings, entries) do
    replace_group(
      ContainerSettings.purge(),
      entries,
      :container_settings_purge,
      :container_settings_import,
      fn {node, name, settings} -> ContainerSettings.import(settings, node, name) end
    )
  end

  defp execute_section(:images_settings, entries) do
    replace_group(
      ImageSettings.purge(),
      entries,
      :image_settings_purge,
      :image_settings_import,
      fn {node, id, settings} -> ImageSettings.import(settings, node, id) end
    )
  end

  defp replace_group(purge_result, entries, purge_operation, persist_operation, persist) do
    with :ok <- Result.normalize_write_result(purge_result, purge_operation) do
      BatchWriter.persist_each(entries, fn entry ->
        entry |> persist.() |> Result.normalize_write_result(persist_operation)
      end)
    end
  end
end
