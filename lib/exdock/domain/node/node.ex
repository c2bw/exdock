defmodule Exdock.Domain.Node do
  @moduledoc """
  Node of the cluster.

  ## Fields
  - `node`
  - `fetched_at`: date when the node data was last fetched
  - `metadata`: live metadata reported by the connected agent
  - `settings`: node settings
  """
  alias Exdock.Domain.Node

  defstruct [
    :node,
    :fetched_at,
    :settings,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          node: String.t(),
          fetched_at: DateTime.t() | nil,
          metadata: map(),
          settings: Node.Settings.t()
        }

  @spec new(String.t(), DateTime.t(), Node.Settings.t()) :: t()
  def new(node, %DateTime{} = fetched_at, %Node.Settings{} = settings) do
    %__MODULE__{
      node: normalize_node(node),
      fetched_at: fetched_at,
      metadata: %{},
      settings: settings
    }
  end

  @spec set_fetched_at(t(), DateTime.t()) :: t()
  def set_fetched_at(%__MODULE__{} = data, %DateTime{} = fetched_at) do
    %{data | fetched_at: DateTime.truncate(fetched_at, :second)}
  end

  @spec put_metadata(t(), map()) :: t()
  def put_metadata(%__MODULE__{} = data, metadata) when is_map(metadata) do
    %{data | metadata: metadata}
  end

  @doc """
  Build an in-memory node before a client refresh has produced durable data.

  `fetched_at` stays nil intentionally: settings can exist before the first
  node snapshot, and `insert/1` persists only the settings side in that state.
  """
  @spec default(String.t()) :: t()
  def default(node) do
    %__MODULE__{
      node: normalize_node(node),
      fetched_at: nil,
      metadata: %{},
      settings: Node.Settings.default()
    }
  end

  @doc """
  Replace user-managed settings while preserving the live node snapshot.
  """
  @spec put_settings(t(), Node.Settings.t()) :: t()
  def put_settings(%__MODULE__{} = data, %Node.Settings{} = settings),
    do: %{data | settings: settings}

  defp normalize_node(node) when is_binary(node), do: node
end
