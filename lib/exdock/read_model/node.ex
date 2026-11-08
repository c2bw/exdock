defmodule Exdock.ReadModel.Node do
  @moduledoc """
  Stable node-detail projection exposed to UI and API consumers.

  Container runtime records are projected into separately keyed core and
  extended maps so consumers never need to reconstruct storage internals.
  """

  defstruct [:node, :info, :containers_core, :containers_extended, :images]

  alias Exdock.ReadModel.Container

  @type container_key :: Container.Key.t()

  @type t :: %__MODULE__{
          node: String.t(),
          info: map(),
          containers_core: %{container_key() => Container.Core.t()},
          containers_extended: %{container_key() => Container.Extended.t()},
          images: list()
        }

  @type node_key :: String.t()
  @type node_map :: %{node_key() => %{fetched_at: DateTime.t() | nil}}

  @doc """
  Returns the last fetched time stored for a node.

  Node keys use the canonical runtime string representation.
  """
  @spec last_fetch(node_map(), node_key()) :: DateTime.t() | nil
  def last_fetch(nodes, node) when is_map(nodes) and is_binary(node) do
    with %{fetched_at: fetched_at} <- Map.get(nodes, node) do
      fetched_at
    end
  end
end
