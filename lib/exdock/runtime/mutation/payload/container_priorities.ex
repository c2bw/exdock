defmodule Exdock.Runtime.Mutation.Payload.ContainerPriorities do
  @moduledoc "Typed collection of container priority changes."

  alias Exdock.Runtime.Mutation.Payload.ContainerPriority

  @enforce_keys [:priorities]
  defstruct [:priorities]

  @type t :: %__MODULE__{priorities: [ContainerPriority.t()]}
end
