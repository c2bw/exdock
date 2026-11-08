defmodule Exdock.Database.ContainerSettings do
  @moduledoc """
  Persistence for user-editable per-container settings.

  Container identity is `{node, name}`. Values stored here are merged into the
  live container structures during refresh/load so priorities, labels, and
  auto-update preferences survive container recreation and server restarts.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Exdock.Database
  alias Exdock.Database.NodeScopedSettings
  alias Exdock.Database.SchemaHelpers
  alias Exdock.Database.StoredAtom
  alias Exdock.Container.SettingsCatalog
  alias Exdock.Container.Policy

  @persisted_fields [:node, :name] ++ SettingsCatalog.fields()
  @upsert_defaults [
    on_conflict: {:replace_all_except, [:node, :name]},
    conflict_target: [:node, :name]
  ]

  @type t :: %__MODULE__{
          node: Exdock.NodeId.t(),
          name: String.t(),
          priority: integer(),
          auto_update: atom(),
          labels: list()
        }

  @type node_id :: Exdock.NodeId.t()

  @doc """
    The container_settings schema stores the user settings for a container.
  """
  @primary_key false
  schema "container_settings" do
    field :node, :string, primary_key: true, autogenerate: false
    field :name, :string, primary_key: true, autogenerate: false
    field :priority, :integer
    field :auto_update, :string
    field :labels, {:array, :string}
  end

  @spec new(map()) :: t()
  def new(%{
        node: node,
        name: name,
        priority: priority,
        auto_update: auto_update,
        labels: labels
      }) do
    %__MODULE__{
      node: node,
      name: name,
      priority: priority,
      auto_update: auto_update,
      labels: labels
    }
  end

  @doc """
   Returns a list of all the settings stored in the database
  """
  @spec load_all() :: [t()]
  def load_all, do: NodeScopedSettings.load_all(Database.ContainerSettings, &to_runtime_format/1)

  @doc """
  Retrieves all container settings for a node.
  """
  @spec load_node(node_id()) :: [t()]
  def load_node(node) when is_binary(node),
    do: NodeScopedSettings.load_node(Database.ContainerSettings, node, &to_runtime_format/1)

  @doc """
    Retrieves a container's settings by its node and name.
  """
  @spec load(node_id(), String.t()) :: t() | nil
  def load(node, container_name) when is_binary(node) and is_binary(container_name) do
    NodeScopedSettings.load(
      Database.ContainerSettings,
      node,
      [name: container_name],
      &to_runtime_format/1
    )
  end

  @doc """
    Inserts the container settings into the database.
  """
  @spec insert(t(), keyword()) :: {:ok, t()} | {:error, Ecto.Changeset.t()} | {:error, term()}
  def insert(%__MODULE__{node: node, auto_update: auto_update} = settings, opts \\ [])
      when is_binary(node) and is_atom(auto_update) do
    settings
    |> container_settings_changeset(persisted_row(settings))
    |> Exdock.Repo.insert(merge_insert_opts(opts))
    |> SchemaHelpers.map_ok(&to_runtime_format/1)
  end

  @doc """
    Removes all settings.
  """
  @spec purge() :: {non_neg_integer(), nil | [term()]}
  def purge, do: NodeScopedSettings.purge(Database.ContainerSettings)

  defp persisted_row(%__MODULE__{} = settings) do
    settings
    |> to_stored_format()
    |> Map.take(@persisted_fields)
  end

  defp to_stored_format(%__MODULE__{auto_update: auto_update} = settings) do
    settings = NodeScopedSettings.to_stored_node(settings)
    %{settings | auto_update: dump_auto_update(auto_update)}
  end

  @spec to_runtime_format(struct()) :: t()
  defp to_runtime_format(%{node: node, auto_update: update} = settings) when is_binary(node) and is_binary(update) do
    # Revalidate the node and restore controlled setting atoms from SQLite text.
    settings = NodeScopedSettings.from_stored_node(settings)
    %{settings | auto_update: load_auto_update(update)}
  end

  defp merge_insert_opts(opts) do
    # Keep caller-provided options dominant so existing callers can override defaults.
    Keyword.merge(@upsert_defaults, opts)
  end

  defp dump_auto_update(auto_update) when is_atom(auto_update), do: StoredAtom.dump(auto_update)

  defp load_auto_update(auto_update) when is_binary(auto_update) do
    StoredAtom.load(
      auto_update,
      SettingsCatalog.auto_update_values(),
      SettingsCatalog.default(:auto_update)
    )
  end

  defp container_settings_changeset(struct, params) do
    struct
    |> cast(params, @persisted_fields)
    |> validate_required([:node, :name, :priority, :auto_update])
    |> validate_number(:priority,
      greater_than_or_equal_to: Policy.min_priority(),
      less_than_or_equal_to: Policy.max_priority()
    )
  end
end
