defmodule Exdock.Protocol.Command.ContainerStop do
  @moduledoc "Validated container stop command."
  @enforce_keys [:id, :container_id]
  defstruct [:id, :container_id]
  @type t :: %__MODULE__{id: String.t(), container_id: String.t()}
end
