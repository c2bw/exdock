defmodule Exdock.Protocol.Command.ImagePull do
  @moduledoc "Validated image pull command."
  @enforce_keys [:id, :image_tag]
  defstruct [:id, :image_tag]
  @type t :: %__MODULE__{id: String.t(), image_tag: String.t()}
end
