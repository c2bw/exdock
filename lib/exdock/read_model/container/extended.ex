defmodule Exdock.ReadModel.Container.Extended do
  @moduledoc """
  Public container telemetry projection.
  """

  alias Exdock.ReadModel.Value

  @empty_resources %{
    rates: %{cpu_usage: nil, used_memory: nil, io: %{read: nil, write: nil}, net: %{rx: nil, tx: nil}},
    records: []
  }

  defstruct logs: nil, resources: @empty_resources

  @type t :: %__MODULE__{logs: map() | nil, resources: map()}

  @spec from_domain(map() | t() | nil) :: t()
  def from_domain(nil), do: empty()
  def from_domain(%__MODULE__{} = extended), do: extended

  def from_domain(extended) when is_map(extended) do
    projected = Value.project(extended)

    %__MODULE__{
      logs: Map.get(projected, :logs),
      resources: Map.get(projected, :resources) || empty_resources()
    }
  end

  @spec empty() :: t()
  def empty, do: %__MODULE__{}

  @spec empty_resources() :: map()
  def empty_resources, do: @empty_resources
end
