defmodule Exdock.Runtime.Mutation.Payload.ImageDeleteLock do
  @moduledoc "Typed image delete-lock mutation payload."

  @enforce_keys [:node, :id, :locked?]
  defstruct [:node, :id, :locked?]

  @type t :: %__MODULE__{node: String.t(), id: String.t(), locked?: boolean()}
end
