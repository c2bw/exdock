defmodule Exdock.Runtime do
  @moduledoc """
  Explicit command and query boundary around Exdock's authoritative runtime.

  The command vocabulary is deliberately finite. This module is the migration
  seam between delivery layers and runtime implementation details; callers do
  not submit functions, storage modules, or state-change payloads.
  """

  alias Exdock.Runtime.Command
  alias Exdock.Runtime.Coordinator
  alias Exdock.Server.Logging

  @type operation_id :: Ecto.UUID.t()

  @spec dispatch(operation_id(), Command.public_t()) :: :ok | {:error, term()}
  def dispatch(operation_id, command) when is_binary(operation_id) do
    with {:ok, normalized_command} <- Command.normalize(command) do
      kind = Command.kind(command)

      dispatch_normalized(operation_id, normalized_command, kind)
    end
  end

  defp dispatch_normalized(operation_id, :clear_errors, _kind),
    do: Logging.submit_clear_errors(operation_id)

  defp dispatch_normalized(operation_id, :run_automation, _kind),
    do: Coordinator.submit_periodic_job(operation_id)

  defp dispatch_normalized(operation_id, command, kind),
    do: Coordinator.submit(operation_id, command, operation_kind: kind)
end
