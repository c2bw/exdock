defmodule Exdock.Database.Nodes do
  use Ecto.Schema
  import Ecto.Changeset
  alias Exdock.Database
  alias Exdock.Database.NodeName
  alias Exdock.Database.SchemaHelpers

  @persisted_fields [:node, :fetched_at]

  @type t :: %__MODULE__{
          node: String.t(),
          fetched_at: DateTime.t()
        }

  @type node_id :: Exdock.NodeId.t()

  @primary_key {:node, :string, autogenerate: false}
  schema "nodes" do
    field(:fetched_at, :utc_datetime)
  end

  @spec new(map()) :: t()
  def new(%{node: node, fetched_at: %DateTime{} = fetched_at}) do
    %__MODULE__{
      node: node,
      fetched_at: fetched_at
    }
  end

  @doc """
    Retrieve all data.
  """
  @spec load_all() :: [t()]
  def load_all() do
    Exdock.Repo.all(Database.Nodes)
    |> Enum.map(&from_database_record/1)
  end

  @doc """
    Retrieve the node.
  """
  @spec load(node_id()) :: t() | nil
  def load(node) when is_binary(node) do
    fetch_stored_record(node)
    |> rehydrate_record()
  end

  @doc """
    Insert the node.
  """
  @spec insert(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def insert(%__MODULE__{} = data) do
    data
    |> nodes_changeset(database_row(data))
    |> Exdock.Repo.insert(on_conflict: {:replace_all_except, [:node]}, conflict_target: [:node])
    |> SchemaHelpers.map_ok(&from_database_record/1)
  end

  defp database_row(%__MODULE__{} = data) do
    data
    |> to_database_format()
    |> Map.take(@persisted_fields)
  end

  defp nodes_changeset(struct, params) do
    struct
    |> cast(params, @persisted_fields)
    |> validate_required([:node, :fetched_at])
  end

  defp fetch_stored_record(node) when is_binary(node) do
    # Persisted rows keep node names as strings; normalize runtime node ids for DB lookup.
    Exdock.Repo.get_by(Database.Nodes, NodeName.query(node))
  end

  defp rehydrate_record(nil), do: nil
  defp rehydrate_record(%__MODULE__{} = data), do: from_database_record(data)

  defp to_database_format(%__MODULE__{} = data) do
    data
    |> NodeName.to_stored_format()
    |> Map.update!(:fetched_at, &DateTime.truncate(&1, :second))
  end

  @spec from_database_record(struct()) :: t()
  defp from_database_record(%{} = data) do
    NodeName.from_stored_format(data)
  end
end
