defmodule Exdock.Server.State.Storage.Cluster.Utils.NodeStorage.Data do
  @moduledoc """
  Thin wrapper around one module's canonical string node-to-data map.

  Identifier normalization belongs to `NodeStorage`; this lower layer rejects
  non-string keys so mixed runtime representations cannot leak into storage.
  """

  defstruct entries: %{}

  @type key :: String.t()
  @type node_entries(value) :: %{key() => value}
  @type t(value) :: %__MODULE__{
          entries: node_entries(value)
        }

  @doc """
  Create a fresh data container for one module's node map.
  """
  @spec new() :: t(term())
  def new(), do: %__MODULE__{entries: %{}}

  @doc """
  Fetch a value for a canonical node name.
  """
  @spec get(t(value), String.t()) :: value | nil when value: term()
  def get(%__MODULE__{entries: entries}, node) when is_binary(node),
    do: Map.get(entries, node)

  @doc """
  Store or update a value for a runtime node name.
  """
  @spec set(t(value), String.t(), value) :: t(value) when value: term()
  def set(%__MODULE__{entries: entries} = data, node, value) when is_binary(node),
    do: %{data | entries: Map.put(entries, node, value)}

  @doc """
  Return the durable string-keyed map for this module.
  """
  @spec get_map(t(value)) :: node_entries(value) when value: term()
  def get_map(%__MODULE__{entries: entries} = _), do: entries

  @doc """
  Remove data for a runtime node name.
  """
  @spec remove(t(value), String.t()) :: t(value) when value: term()
  def remove(%__MODULE__{entries: entries} = data, node) when is_binary(node),
    do: %{data | entries: Map.delete(entries, node)}
end
