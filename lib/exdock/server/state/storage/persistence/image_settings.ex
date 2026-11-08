defmodule Exdock.Server.State.Storage.Persistence.ImageSettings do
  @moduledoc """
  Repository and mapper for user-managed image settings.
  """

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.SettingsAdapter
  alias Exdock.Domain.Image.Settings

  @type node_id :: Exdock.NodeId.t()

  @spec load(node_id(), String.t()) :: Settings.t() | nil
  def load(node, id)
      when is_binary(node) and is_binary(id) do
    node
    |> Database.ImageSettings.load(id)
    |> SettingsAdapter.load(&Settings.from_persisted/1)
  end

  @spec load_node(node_id()) :: %{String.t() => Settings.t()}
  def load_node(node) when is_binary(node) do
    node
    |> Database.ImageSettings.load_node()
    |> Map.new(fn row -> {row.id, Settings.from_persisted(row)} end)
  end

  @spec insert(Settings.t(), node_id(), String.t()) ::
          {:ok, Database.ImageSettings.t()} | {:error, term()}
  def insert(%Settings{} = settings, node, id)
      when is_binary(node) and is_binary(id) do
    settings
    |> SettingsAdapter.attributes(%{node: node, id: id})
    |> Database.ImageSettings.new()
    |> Database.ImageSettings.insert()
  end

  @spec import(map(), node_id(), String.t()) ::
          {:ok, Database.ImageSettings.t()} | {:error, term()}
  def import(%{} = unsafe, node, id)
      when is_binary(node) and is_binary(id) do
    SettingsAdapter.import(unsafe, &Settings.from_import/1, &insert(&1, node, id))
  end

  @spec purge() :: {non_neg_integer(), nil | [term()]}
  def purge, do: Database.ImageSettings.purge()
end
