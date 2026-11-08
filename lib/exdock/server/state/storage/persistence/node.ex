defmodule Exdock.Server.State.Storage.Persistence.Node do
  @moduledoc """
  Repository and mapper for persisted node snapshots and node settings.

  This is the only layer that knows both Ecto node schemas and runtime node
  structures.
  """

  alias Exdock.Database
  alias Exdock.Domain.Node, as: RuntimeNode
  alias Exdock.Domain.Node.Settings
  alias Exdock.Server.State.Storage.Persistence.Error

  @type node_id :: Exdock.NodeId.t()

  @spec known?(term()) :: boolean()
  def known?(node) when is_binary(node) do
    Database.NodeName.validate(node) == :ok and not is_nil(Database.Nodes.load(node))
  end

  def known?(_node), do: false

  @spec load(node_id()) :: RuntimeNode.t() | nil
  def load(node) when is_binary(node) do
    case Database.Nodes.load(node) do
      nil ->
        nil

      %Database.Nodes{node: stored_node, fetched_at: fetched_at} ->
        RuntimeNode.new(stored_node, fetched_at, load_settings(stored_node) || Settings.default())
    end
  end

  @spec insert(RuntimeNode.t()) :: :ok | {:error, Error.t()}
  def insert(%RuntimeNode{} = node) do
    with :ok <- persist_snapshot(node),
         :ok <- normalize(insert_settings(node.settings, node.node), :node_settings_insert) do
      :ok
    end
  end

  @spec reload_settings(RuntimeNode.t()) :: RuntimeNode.t()
  def reload_settings(%RuntimeNode{node: node} = data) do
    RuntimeNode.put_settings(data, load_settings(node) || Settings.default())
  end

  @spec load_settings(node_id()) :: Settings.t() | nil
  def load_settings(node) when is_binary(node) do
    case Database.NodeSettings.load(node) do
      nil -> nil
      %Database.NodeSettings{web_ui: web_ui} -> Settings.new(web_ui)
    end
  end

  @spec insert_settings(Settings.t(), node_id()) ::
          {:ok, Database.NodeSettings.t()} | {:error, Ecto.Changeset.t()}
  def insert_settings(%Settings{web_ui: web_ui}, node)
      when is_binary(node) do
    %{node: node, web_ui: web_ui}
    |> Database.NodeSettings.new()
    |> Database.NodeSettings.insert()
  end

  @spec import_settings(map(), node_id()) ::
          {:ok, Database.NodeSettings.t()} | {:error, Ecto.Changeset.t()}
  def import_settings(%{} = unsafe, node) when is_binary(node) do
    unsafe
    |> Settings.from_import()
    |> insert_settings(node)
  end

  @spec purge_settings() :: {non_neg_integer(), nil | [term()]}
  def purge_settings, do: Database.NodeSettings.purge()

  @doc false
  def purge, do: purge_settings()

  defp persist_snapshot(%RuntimeNode{fetched_at: nil}), do: :ok

  defp persist_snapshot(%RuntimeNode{node: node, fetched_at: %DateTime{} = fetched_at}) do
    %{node: node, fetched_at: fetched_at}
    |> Database.Nodes.new()
    |> Database.Nodes.insert()
    |> normalize(:node_data_insert)
  end

  defp normalize(result, step),
    do: Exdock.Server.State.Storage.Persistence.Result.normalize_insert_result(result, step)
end
