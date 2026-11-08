defmodule Exdock.Runtime.Mutation.Payload.ContainerResources do
  @moduledoc "Typed container resource-sample mutation payload."

  alias Exdock.Domain.Container.Resources.Record

  @enforce_keys [:node, :id, :resources]
  defstruct [:node, :id, :resources]

  @type t :: %__MODULE__{node: String.t(), id: String.t(), resources: Record.t()}
end
