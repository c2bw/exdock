defmodule Exdock.Runtime.Command.Validation do
  @moduledoc false

  alias Exdock.NodeId

  @spec map_all(list(), (term() -> {:ok, term()} | {:error, term()})) ::
          {:ok, list()} | {:error, term()}
  defdelegate map_all(values, mapper), to: Exdock.Result, as: :traverse

  @spec runtime_node(term()) :: {:ok, String.t()} | {:error, {:invalid_node, NodeId.normalize_error()}}
  def runtime_node(node) do
    case NodeId.normalize(node) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, reason} -> {:error, {:invalid_node, reason}}
    end
  end
end
