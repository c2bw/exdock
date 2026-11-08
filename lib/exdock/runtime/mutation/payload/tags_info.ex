defmodule Exdock.Runtime.Mutation.Payload.TagsInfo do
  @moduledoc "Typed registry tag-information mutation payload."

  alias Exdock.Domain.TagInfo

  @enforce_keys [:tags]
  defstruct [:tags]

  @type t :: %__MODULE__{tags: [TagInfo.t()]}
end
