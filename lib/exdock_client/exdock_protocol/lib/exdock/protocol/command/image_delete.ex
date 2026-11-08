defmodule Exdock.Protocol.Command.ImageDelete do
  @moduledoc "Validated image deletion command."
  @enforce_keys [:id, :image_id]
  defstruct [:id, :image_id]
  @type t :: %__MODULE__{id: String.t(), image_id: String.t()}
end
