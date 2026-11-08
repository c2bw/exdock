defmodule Exdock.Protocol.Command.ContainerLogs do
  @moduledoc "Validated container logs command."
  @enforce_keys [:id, :container_id, :opts]
  defstruct [:id, :container_id, :opts]
  @type t :: %__MODULE__{id: String.t(), container_id: String.t(), opts: list()}
end
