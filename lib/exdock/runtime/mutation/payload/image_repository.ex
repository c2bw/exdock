defmodule Exdock.Runtime.Mutation.Payload.ImageRepository do
  @moduledoc "One typed image-to-repository override."

  @enforce_keys [:image, :url]
  defstruct [:image, :url]

  @type t :: %__MODULE__{image: String.t(), url: String.t()}
end
