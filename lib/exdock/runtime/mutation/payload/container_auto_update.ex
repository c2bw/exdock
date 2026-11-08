defmodule Exdock.Runtime.Mutation.Payload.ContainerAutoUpdate do
  @moduledoc "Typed container auto-update mutation payload."

  @enforce_keys [:node, :name, :policy]
  defstruct [:node, :name, :policy]

  @type policy :: :enabled | :disabled | :passthrough
  @type t :: %__MODULE__{node: String.t(), name: String.t(), policy: policy()}
end
