defmodule Exdock.Runtime.Mutation.Payload.NodeSetting do
  @moduledoc "Typed node-setting mutation payload."

  @enforce_keys [:node, :key, :value]
  defstruct [:node, :key, :value]

  @type t :: %__MODULE__{node: String.t(), key: atom(), value: term()}
end
