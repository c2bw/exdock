defmodule Exdock.Server.Jobs.Payload.ContainerAction do
  @moduledoc "Metadata shared by container start, stop, restart, logs, and recreate jobs."

  @enforce_keys [:node, :container]
  defstruct [:node, :container]

  @type t :: %__MODULE__{node: String.t(), container: String.t()}

  @spec new(String.t(), String.t()) :: t()
  def new(node, container) when is_binary(node) and is_binary(container),
    do: %__MODULE__{node: node, container: container}
end
