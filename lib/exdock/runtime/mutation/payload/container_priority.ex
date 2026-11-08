defmodule Exdock.Runtime.Mutation.Payload.ContainerPriority do
  @moduledoc "One typed container-priority mutation payload."

  @enforce_keys [:node, :name, :priority]
  defstruct [:node, :name, :priority]

  @type t :: %__MODULE__{node: String.t(), name: String.t(), priority: integer()}
end
