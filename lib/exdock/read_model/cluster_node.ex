defmodule Exdock.ReadModel.ClusterNode do
  @moduledoc "Public connected-node projection consumed by delivery layers."

  alias Exdock.ReadModel.Value

  defstruct [:node, :fetched_at, :settings, metadata: %{}]

  @type t :: %__MODULE__{
          node: String.t(),
          fetched_at: DateTime.t() | nil,
          metadata: map(),
          settings: map()
        }

  def from_domain(%__MODULE__{} = node), do: node

  @spec from_domain(map()) :: t()
  def from_domain(%{node: node, fetched_at: fetched_at, metadata: metadata, settings: settings}) do
    %__MODULE__{
      node: node,
      fetched_at: fetched_at,
      metadata: Value.project(metadata),
      settings: Value.project(settings)
    }
  end
end
