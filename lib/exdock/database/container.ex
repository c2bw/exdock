defmodule Exdock.Database.Container do
  @moduledoc """
  Persistence adapter for durable container core data.

  `Exdock.Database.Container.Row` owns the Ecto schema while this module
  translates between stored rows and application-facing `Record` structs.
  Runtime-only data such as logs and resource samples lives in the in-memory
  container `extended` structure. This schema stores the durable identity,
  Docker state, image relationship, settings-derived priority inputs, and a soft
  deletion marker used when a node refresh no longer reports a container.
  """

  import Ecto.Query
  alias Exdock.Database
  alias Exdock.Database.NodeName
  alias Exdock.Database.Container.Changeset
  alias Exdock.Database.Container.Mapper
  alias Exdock.Database.Container.Record
  alias Exdock.Database.Container.Row
  alias Exdock.Database.SchemaHelpers
  alias Exdock.Database.Compare

  @type t :: Record.t()
  @type node_key() :: String.t()

  @spec new(map()) :: t()
  def new(attributes) when is_map(attributes), do: struct!(Record, attributes)

  @doc """
   Returns a list of the containers for a specific node

    ## Parameters
    - `node` - the node to retrieve the containers from.
    - `load_deleted` - whether to load deleted containers or not: `true` or `false` (default: `false`).
  """
  @spec load_node(node_key(), boolean()) :: {:ok, [t()]} | {:error, term()}
  def load_node(node, load_deleted \\ false) when is_binary(node) and is_boolean(load_deleted) do
    node
    |> container_query(load_deleted)
    |> Exdock.Repo.all()
    |> Mapper.to_records()
  end

  @doc """
    Retrieves a container by its node and name

    If load_deleted is set:
    - `true`  - the container is retrieved regardless of its deletion status.
    - `false` - the container is retrieved only if not marked as deleted.
  """
  @spec load(node_key(), String.t(), boolean()) :: {:ok, t() | nil} | {:error, term()}
  def load(node, name, load_deleted \\ false)
      when is_binary(node) and is_binary(name) and is_boolean(load_deleted) do
    node
    |> load_filters(name, load_deleted)
    |> load_container()
  end

  @spec insert(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()} | {:error, term()}
  def insert(%Record{} = container) do
    # Containers are persisted only after their node-local image exists. The
    # foreign key is denormalized, so checking here keeps the caller's error
    # simple instead of returning a low-level constraint changeset.
    case validate_known_images([container]) do
      :ok ->
        # Convert node and JSON-like fields to the storage format expected by
        # the schema before relying on the changeset validations.
        with {:ok, stored_row} <- Mapper.to_row(container) do
          stored_row
          |> Changeset.build()
          |> Exdock.Repo.insert(on_conflict: {:replace_all_except, [:node, :name]}, conflict_target: [:node, :name])
          |> map_inserted_container()
        end

      {:error, :empty_image_id} = error ->
        error
    end
  end

  @doc false
  @spec insert_all([t()]) :: :ok | {:error, Ecto.Changeset.t()} | {:error, :empty_image_id}
  def insert_all(containers) when is_list(containers) do
    with :ok <- validate_known_images(containers),
         {:ok, stored_rows} <- Mapper.to_rows(containers),
         {:ok, rows} <-
           SchemaHelpers.validated_rows(
             stored_rows,
             &Changeset.build/1,
             Row.__schema__(:fields)
           ) do
      Exdock.Repo.insert_all(Row, rows,
        on_conflict: {:replace_all_except, [:node, :name]},
        conflict_target: [:node, :name]
      )

      :ok
    end
  end

  @doc """
   Update the set by marking as deleted all containers whose name is not in the list.
  """
  @spec mark_set(node_key(), [String.t()]) :: {non_neg_integer(), nil | [term()]}
  def mark_set(node, not_deleted) when is_binary(node) and is_list(not_deleted) do
    node = NodeName.stored!(node)

    from(c in Row,
      where: c.node == ^node and c.name not in ^not_deleted,
      update: [set: [is_deleted: true]]
    )
    |> Exdock.Repo.update_all([])
  end

  @doc """
    Return whether two containers are the same or not.
  """
  @spec same?(t(), t()) :: boolean()
  def same?(%Record{} = a, %Record{} = b), do: Compare.compare(a, b)

  @doc """
    Returns the images ids used by containers of a node.
  """
  @spec images_ids(node_key(), boolean()) :: [String.t()]
  def images_ids(node, load_deleted \\ false) when is_binary(node) and is_boolean(load_deleted) do
    node
    |> container_query(load_deleted)
    |> select([c], c.image_id)
    |> Exdock.Repo.all()
  end

  defp validate_known_images(containers) do
    requested_keys =
      MapSet.new(containers, fn %Record{node: node, image_id: image_id} ->
        Database.Image.generate_key(node, image_id)
      end)

    stored_keys =
      from(i in Database.Image.Row,
        where: i.image_key in ^MapSet.to_list(requested_keys),
        select: i.image_key
      )
      |> Exdock.Repo.all()
      |> MapSet.new()

    if MapSet.subset?(requested_keys, stored_keys), do: :ok, else: {:error, :empty_image_id}
  end

  defp load_container(filters) when is_list(filters) do
    Row
    |> Exdock.Repo.get_by(filters)
    |> to_record()
  end

  defp to_record(nil), do: {:ok, nil}
  defp to_record(%Row{} = container), do: Mapper.to_record(container)

  defp map_inserted_container({:ok, %Row{} = row}), do: Mapper.to_record(row)
  defp map_inserted_container({:error, %Ecto.Changeset{} = changeset}), do: {:error, changeset}

  defp load_filters(node, name, load_deleted) do
    node
    |> container_filters(load_deleted)
    |> Keyword.put(:name, name)
  end

  defp container_filters(node, true), do: [node: NodeName.stored!(node)]
  defp container_filters(node, false), do: [node: NodeName.stored!(node), is_deleted: false]

  defp container_query(node, load_deleted) do
    from(c in Row, where: ^container_filters(node, load_deleted))
  end
end
