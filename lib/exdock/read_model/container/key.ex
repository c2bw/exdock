defmodule Exdock.ReadModel.Container.Key do
  @moduledoc """
  Canonical identity used to join container core and extended projections.
  """

  @enforce_keys [:name, :id]
  defstruct [:name, :id]

  @type t :: %__MODULE__{name: String.t(), id: String.t()}

  @spec new(String.t(), String.t()) :: t()
  def new(name, id) when is_binary(name) and is_binary(id), do: %__MODULE__{name: name, id: id}

  @spec from_container(map()) :: t()
  def from_container(%{name: name, id: id}), do: new(name, id)
end
