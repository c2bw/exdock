defmodule Exdock.Protocol.Command.ContainerStart do
  @moduledoc "Validated container start command."
  @enforce_keys [:id, :container_id]
  defstruct [:id, :container_id]
  @type t :: %__MODULE__{id: String.t(), container_id: String.t()}
end
