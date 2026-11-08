defmodule Exdock.Database.Image do
  @moduledoc """
  Persistence adapter for Docker images known on each node.

  `Exdock.Database.Image.Row` owns the Ecto schema. This adapter translates
  those rows into application-facing `Record` structs, which keeps stored tag
  encoding and node normalization out of runtime state. Images are keyed by
  `{node, id}` and also expose a generated `image_key` so
  persisted containers can reference the node-local image they were created
  from. Tags are stored as a comma-separated string in SQLite and expanded back
  to lists at the database boundary.
  """

  alias Exdock.Database.NodeName
  alias Exdock.Database.Image.Changeset
  alias Exdock.Database.Image.Mapper
  alias Exdock.Database.Image.Record
  alias Exdock.Database.Image.Row
  alias Exdock.Database.SchemaHelpers
  alias Exdock.Database.Compare
  import Ecto.Query

  @type t :: Record.t()
  @type node_id :: Exdock.NodeId.t()
  @spec new(map()) :: t()
  def new(image) when is_map(image) do
    # Runtime image structs use validated node strings and list tags; DB schemas
    # keep the same node identity and serialize tags.
    struct!(Record, Map.take(image, Record.fields()))
  end

  @doc """
    Retrieve all the images for a node.
  """
  @spec by_node(node_id()) :: [t()]
  def by_node(node) when is_binary(node) do
    node
    |> query_by_node()
    |> Exdock.Repo.all()
    |> Mapper.to_records()
  end

  @doc """
    Retrieve the image on a node by its id.
  """
  @spec by_node_and_id(node_id(), String.t()) :: t() | nil
  def by_node_and_id(node, id) when is_binary(node) and is_binary(id) do
    load_node_image(node: NodeName.stored!(node), id: id)
  end

  @doc """
    Retrieve an image on a node by its digest.

    More than one image on a node may have the same digest, especially when
    Docker reports an empty digest. The image with the lowest id is returned so
    the result is deterministic.
  """
  @spec by_node_and_digest(node_id(), String.t()) :: t() | nil
  def by_node_and_digest(node, digest) when is_binary(node) and is_binary(digest) do
    load_node_image(node: NodeName.stored!(node), digest: digest)
  end

  @doc """
    Insert an image into the database.

    ## Parameters
    - `image` - The image to insert.
  """
  @spec insert(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def insert(%Record{} = image) do
    image
    |> Mapper.to_row()
    |> Changeset.build()
    |> Exdock.Repo.insert(on_conflict: {:replace_all_except, [:id, :node]}, conflict_target: [:id, :node])
    |> SchemaHelpers.map_ok(&Mapper.to_record/1)
  end

  @doc false
  @spec insert_all([t()]) :: :ok | {:error, Ecto.Changeset.t()}
  def insert_all(images) when is_list(images) do
    with stored_rows <- Mapper.to_rows(images),
         {:ok, rows} <-
           SchemaHelpers.validated_rows(
             stored_rows,
             &Changeset.build/1,
             Row.__schema__(:fields)
           ) do
      Exdock.Repo.insert_all(Row, rows,
        on_conflict: {:replace_all_except, [:id, :node]},
        conflict_target: [:id, :node]
      )

      :ok
    end
  end

  @doc """
      Update the nodeset, marking as deleted all images not in the provided list.
  """
  @spec nodeset_update(node_id(), [String.t()]) :: {non_neg_integer(), nil | [term()]}
  def nodeset_update(node, images_ids) when is_binary(node) and is_list(images_ids) do
    node
    |> query_by_node()
    |> where([i], i.id not in ^images_ids)
    |> Exdock.Repo.delete_all()
  end

  @doc """
    Return whether two images are the same or not.
  """
  @spec same?(t(), t()) :: boolean()
  def same?(%Record{build_date: a_date} = a, %Record{build_date: b_date} = b) do
    Compare.compare(
      %{a | build_date: a_date |> DateTime.truncate(:second)},
      %{b | build_date: b_date |> DateTime.truncate(:second)}
    )
  end

  @doc """
  Generate a composite key from node and id
  """
  @spec generate_key(node_id(), String.t()) :: String.t()
  def generate_key(node, id) when is_binary(node) and is_binary(id), do: Mapper.key(node, id)

  defp load_node_image(filters) when is_list(filters) do
    Row
    |> where(^filters)
    |> order_by([i], asc: i.id)
    |> limit(1)
    |> Exdock.Repo.one()
    |> map_optional_record()
  end

  defp map_optional_record(nil), do: nil
  defp map_optional_record(%Row{} = image), do: Mapper.to_record(image)

  defp query_by_node(node) when is_binary(node) do
    node = NodeName.stored!(node)
    from(i in Row, where: i.node == ^node)
  end
end
