defmodule Exdock.Database.ImageSettings do
  @moduledoc """
  Persists per-node image settings that are controlled by the UI.

  Image settings are keyed by both node and image id because Docker image ids are
  node-local in Exdock's model. Node names remain validated strings in both
  server state and SQLite, with validation kept at this boundary.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Exdock.Database
  alias Exdock.Database.NodeScopedSettings
  alias Exdock.Database.SchemaHelpers

  @persisted_fields [:id, :node, :delete_lock]

  @derive {Jason.Encoder, only: [:id, :node, :delete_lock]}

  @type t :: %__MODULE__{
          id: String.t(),
          node: Exdock.NodeId.t(),
          delete_lock: boolean
        }

  @type node_id :: Exdock.NodeId.t()

  @doc """
    The image_settings schema stores the user settings for an image.
  """
  @primary_key false
  schema "image_settings" do
    field :id, :string, primary_key: true, autogenerate: false
    field :node, :string, primary_key: true, autogenerate: false
    field :delete_lock, :boolean
  end

  @spec new(map()) :: t()
  def new(%{delete_lock: delete_lock, node: node, id: id})
      when is_boolean(delete_lock) and is_binary(node) and is_binary(id) do
    %__MODULE__{
      id: id,
      node: node,
      delete_lock: delete_lock
    }
  end

  @doc """
   Returns a list of all the settings stored in the database
  """
  @spec load_all() :: [t()]
  def load_all, do: NodeScopedSettings.load_all(Database.ImageSettings, &from_database_record/1)

  @doc """
  Retrieves all image settings for a node.
  """
  @spec load_node(node_id()) :: [t()]
  def load_node(node) when is_binary(node),
    do: NodeScopedSettings.load_node(Database.ImageSettings, node, &from_database_record/1)

  @doc """
    Retrieves an image's settings by its node and id.
  """
  @spec load(node_id(), String.t()) :: t() | nil
  def load(node, id) when is_binary(node) and is_binary(id) do
    NodeScopedSettings.load(Database.ImageSettings, node, [id: id], &from_database_record/1)
  end

  @doc """
    Inserts the image settings into the database.
  """
  @spec insert(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()} | {:error, term()}
  def insert(%__MODULE__{} = settings) do
    # Validate the runtime node identifier before upsert.
    settings
    |> image_settings_changeset(database_row(settings))
    |> Exdock.Repo.insert(on_conflict: {:replace_all_except, [:node, :id]}, conflict_target: [:node, :id])
    |> SchemaHelpers.map_ok(&from_database_record/1)
  end

  defp database_row(%__MODULE__{} = settings) do
    settings
    |> to_database_format()
    |> Map.take(@persisted_fields)
  end

  @doc """
    Removes all settings.
  """
  @spec purge() :: {non_neg_integer(), nil | [term()]}
  def purge, do: NodeScopedSettings.purge(Database.ImageSettings)

  defp to_database_format(%__MODULE__{} = settings), do: NodeScopedSettings.to_stored_node(settings)

  @spec from_database_record(struct()) :: t()
  defp from_database_record(%{node: node} = settings) when is_binary(node) do
    # Revalidate the node value expected by runtime and matcher logic.
    NodeScopedSettings.from_stored_node(settings)
  end

  defp image_settings_changeset(struct, params) do
    struct
    |> cast(params, [:id, :node, :delete_lock])
    |> validate_required([:id, :node])
  end
end
