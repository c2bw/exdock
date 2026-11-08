defmodule Exdock.Protocol.Command.ContainerRecreate do
  @moduledoc "Validated container recreation command."
  @enforce_keys [:id, :container_id, :pull_image]
  defstruct [:id, :container_id, :pull_image]
  @type t :: %__MODULE__{id: String.t(), container_id: String.t(), pull_image: boolean()}
end
