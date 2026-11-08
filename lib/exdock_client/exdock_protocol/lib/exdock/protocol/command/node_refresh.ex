defmodule Exdock.Protocol.Command.NodeRefresh do
  @moduledoc "Validated node refresh command."
  @enforce_keys [:id, :retrieve_resources]
  defstruct [:id, :retrieve_resources]
  @type t :: %__MODULE__{id: String.t(), retrieve_resources: boolean()}
end
