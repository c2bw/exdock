defmodule Exdock.Database.NodeSettings do
  @moduledoc """
  Persists user-editable settings for each connected node.

  Nodes remain validated strings in server state and SQLite. This module keeps
  validation at the database boundary so restored data has the runtime shape.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Exdock.Database
  alias Exdock.Database.NodeScopedSettings
  alias Exdock.Database.SchemaHelpers

  @persisted_fields [:node, :web_ui]

  @type t :: %__MODULE__{
          node: String.t(),
          web_ui: String.t()
        }

  @type node_id :: Exdock.NodeId.t()

  @primary_key {:node, :string, autogenerate: false}
  schema "node_settings" do
    field :web_ui, :string
  end

  @spec new(map()) :: t()
  def new(%{node: node, web_ui: web_ui})
      when is_binary(node) and is_binary(web_ui) do
    %__MODULE__{
      node: node,
      web_ui: web_ui
    }
  end

  @spec load_all() :: [t()]
  def load_all, do: NodeScopedSettings.load_all(Database.NodeSettings, &from_database_record/1)

  @spec load(node_id()) :: t() | nil
  def load(node) when is_binary(node) do
    NodeScopedSettings.load(Database.NodeSettings, node, [], &from_database_record/1)
  end

  @spec insert(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def insert(%__MODULE__{} = settings, opts \\ []) do
    opts = opts |> Keyword.put_new(:on_conflict, :replace_all)

    # Upserts let imports and UI edits share the same persistence path.
    settings
    |> node_settings_changeset(database_row(settings))
    |> Exdock.Repo.insert(opts)
    |> SchemaHelpers.map_ok(&from_database_record/1)
  end

  defp database_row(%__MODULE__{} = settings) do
    settings
    |> to_database_format()
    |> Map.take(@persisted_fields)
  end

  @spec purge() :: {non_neg_integer(), nil | [term()]}
  def purge, do: NodeScopedSettings.purge(Database.NodeSettings)

  defp node_settings_changeset(struct, params) do
    struct
    # A blank web UI is the valid default meaning "no direct UI URL known".
    # Keep it as "" instead of letting Ecto's default empty-value handling turn
    # it into nil, which violates the database column constraint.
    |> cast(params, [:node, :web_ui], empty_values: [])
    |> validate_required([:node])
  end

  defp to_database_format(%__MODULE__{} = settings) do
    NodeScopedSettings.to_stored_node(settings)
  end

  @spec from_database_record(struct()) :: t()
  defp from_database_record(%{} = settings) do
    # Revalidate node names read from durable storage.
    NodeScopedSettings.from_stored_node(settings)
  end
end
