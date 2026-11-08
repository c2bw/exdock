defmodule Exdock.AgentRuntime do
  @moduledoc """
  Fixed entrypoint for the server-supplied agent runtime bundle.

  The base client invokes only this module after validating and loading a bundle;
  individual server messages cannot select modules or functions.
  """

  alias Exdock.ClientLib
  alias Exdock.AgentRuntime.{Executor, Wire}

  # This module is compiled into the server-provided runtime bundle. The
  # implementation it delegates to is supplied by the independently packaged
  # client runtime, so it is intentionally absent from the server application.
  @compile {:no_warn_undefined, {Exdock.ClientLib, :start_link, 1}}
  @compile {:no_warn_undefined, {Exdock.ClientLib, :execute_command, 1}}

  @spec start_link({String.t(), pid()}) :: GenServer.on_start()
  def start_link({node, owner}) when is_binary(node) and is_pid(owner),
    do: ClientLib.start_link({node, owner, Executor, Wire})

  @spec execute(map()) :: :ok
  def execute(command) when is_map(command), do: ClientLib.execute_command(command)
end
