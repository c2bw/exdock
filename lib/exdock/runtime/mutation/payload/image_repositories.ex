defmodule Exdock.Runtime.Mutation.Payload.ImageRepositories do
  @moduledoc "Typed collection of image repository overrides."

  alias Exdock.Runtime.Mutation.Payload.ImageRepository

  @enforce_keys [:overrides]
  defstruct [:overrides]

  @type t :: %__MODULE__{overrides: [ImageRepository.t()]}
end
