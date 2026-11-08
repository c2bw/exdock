defmodule Exdock.Database.NodeScopedSettings do
  @moduledoc """
  Shared persistence primitives for settings keyed by a runtime node id.

  Schemas retain their own fields, changesets, identities, and upsert policy;
  this module only owns the repeated query and node-format boundary.
  """

  import Ecto.Query

  alias Exdock.Database.NodeName
  alias Exdock.Repo

  @spec load_all(module(), (struct() -> term())) :: [term()]
  def load_all(schema, from_stored) when is_atom(schema) and is_function(from_stored, 1) do
    schema
    |> Repo.all()
    |> Enum.map(from_stored)
  end

  @spec load_node(module(), Exdock.NodeId.t(), (struct() -> term())) :: [term()]
  def load_node(schema, node, from_stored)
      when is_atom(schema) and is_binary(node) and is_function(from_stored, 1) do
    schema
    |> where([record], record.node == ^NodeName.stored!(node))
    |> Repo.all()
    |> Enum.map(from_stored)
  end

  @spec load(module(), Exdock.NodeId.t(), keyword(), (struct() -> term())) :: term() | nil
  def load(schema, node, identity, from_stored)
      when is_atom(schema) and is_binary(node) and is_list(identity) and is_function(from_stored, 1) do
    case Repo.get_by(schema, NodeName.query(node) ++ identity) do
      nil -> nil
      record -> from_stored.(record)
    end
  end

  @spec purge(module()) :: {non_neg_integer(), nil | [term()]}
  def purge(schema) when is_atom(schema), do: Repo.delete_all(schema)

  @spec to_stored_node(struct()) :: struct()
  def to_stored_node(%{node: node} = record) when is_binary(node),
    do: %{record | node: NodeName.dump(node)}

  @spec from_stored_node(struct()) :: struct()
  def from_stored_node(%{node: node} = record) when is_binary(node),
    do: %{record | node: NodeName.load(node)}
end
