defmodule Exdock.Client.Connection.RuntimeExecutor do
  @moduledoc """
  Execution boundary for commands handled by the dynamically installed runtime.

  Keeping this adapter in connection state lets the TCP client route commands
  without hard-coding the runtime module into its mailbox handling.
  """

  @compile {:no_warn_undefined, Exdock.AgentRuntime}

  @callback execute(term()) :: term()

  @spec execute(term()) :: term()
  def execute(command), do: Exdock.AgentRuntime.execute(command)
end
