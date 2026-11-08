defmodule Exdock.ClientLib.Execution do
  @moduledoc "Builds the explicit execution envelope consumed by the fixed one-argument agent executor."

  @type t :: {:exdock_execution, map(), term()}

  @spec wrap(map(), term()) :: t()
  def wrap(command, context) when is_map(command), do: {:exdock_execution, command, context}
end
