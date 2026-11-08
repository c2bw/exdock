defmodule Exdock.Database.NodeName do
  @moduledoc """
  Converts node identifiers at database boundaries.

  Runtime and SQLite node identifiers are validated strings.
  """

  alias Exdock.NodeId

  @type invalid_reason :: :empty | :too_long | :invalid_format | :reserved

  @spec dump(String.t()) :: String.t()
  def dump(node) when is_binary(node), do: stored!(node)

  @doc """
  Returns the validated string form used in SQLite.
  """
  @spec stored!(String.t()) :: String.t()
  def stored!(node) when is_binary(node) do
    case validate(node) do
      :ok -> node
      {:error, reason} -> raise ArgumentError, "invalid node name #{inspect(node)}: #{reason}"
    end
  end

  def stored!(node), do: raise(ArgumentError, "invalid node name type #{inspect(node)}")

  @doc false
  @spec to_stored_format(struct()) :: struct()
  def to_stored_format(%{node: node} = data) when is_binary(node), do: data

  @doc """
  Rehydrates trusted node names read from Exdock's own database.

  Values remain strings so database restoration cannot allocate atoms.
  """
  @spec load(String.t()) :: String.t()
  def load(node) when is_binary(node) do
    case NodeId.validate(node) do
      :ok ->
        node

      {:error, _reason} ->
        raise ArgumentError, "invalid node name #{inspect(node)}"
    end
  end

  def load(node), do: raise(ArgumentError, "invalid node name type #{inspect(node)}")

  @doc false
  @spec from_stored_format(struct()) :: struct()
  def from_stored_format(%{node: node} = data) do
    %{data | node: load(node)}
  end

  @doc false
  @spec query(String.t()) :: [{:node, String.t()}]
  def query(node) when is_binary(node), do: [node: stored!(node)]

  # Expose a single boundary where invalid data is rejected so DB call sites can
  # rely on the same name-shape checks used by the TCP registration boundary.
  @doc false
  @spec validate(term()) :: :ok | {:error, invalid_reason()}
  def validate(node), do: NodeId.validate(node)
end
