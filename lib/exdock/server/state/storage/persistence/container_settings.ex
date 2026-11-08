defmodule Exdock.Server.State.Storage.Persistence.ContainerSettings do
  @moduledoc """
  Repository and mapper for user-managed container settings.
  """

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.SettingsAdapter
  alias Exdock.Domain.Container.Settings

  @type node_id :: Exdock.NodeId.t()

  @spec load(node_id(), String.t()) :: Settings.t() | nil
  def load(node, name)
      when is_binary(node) and is_binary(name) do
    node
    |> Database.ContainerSettings.load(name)
    |> SettingsAdapter.load(&Settings.from_persisted/1)
  end

  @spec load_node(node_id()) :: %{String.t() => Settings.t()}
  def load_node(node) when is_binary(node) do
    node
    |> Database.ContainerSettings.load_node()
    |> Map.new(fn row -> {row.name, Settings.from_persisted(row)} end)
  end

  @spec insert(Settings.t(), node_id(), String.t()) ::
          {:ok, Database.ContainerSettings.t()} | {:error, term()}
  def insert(%Settings{} = settings, node, name)
      when is_binary(node) and is_binary(name) do
    settings
    |> attributes(node, name)
    |> Database.ContainerSettings.new()
    |> Database.ContainerSettings.insert()
  end

  @spec import(map(), node_id(), String.t()) ::
          {:ok, Database.ContainerSettings.t()} | {:error, term()}
  def import(%{} = unsafe, node, name)
      when is_binary(node) and is_binary(name) do
    SettingsAdapter.import(unsafe, &Settings.from_import/1, &insert(&1, node, name))
  end

  @spec purge() :: {non_neg_integer(), nil | [term()]}
  def purge, do: Database.ContainerSettings.purge()

  defp attributes(%Settings{} = settings, node, name) do
    SettingsAdapter.attributes(settings, %{node: node, name: name})
  end
end
