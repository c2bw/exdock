defmodule Exdock.ClientLib.Container.Recreator do
  @moduledoc """
  Recreates a Docker container with compensating rollback for every destructive
  step before the replacement is committed.

  The public facade owns progress delivery and operator-facing results.
  `Workflow` owns Docker sequencing and rollback state.
  """

  require Logger

  alias Exdock.ClientLib
  alias Exdock.ClientLib.Container.DockerOps
  alias Exdock.ClientLib.Container.Recreator.{Failure, Workflow}
  alias Exdock.ClientLib.Utils
  alias Exdock.Docker.Error
  alias Exdock.Protocol.Messages

  @type success :: String.t() | %{id: String.t(), warning: String.t()}

  @spec recreate(term(), String.t(), atom(), String.t() | nil, module(), keyword()) ::
          {:ok, success()} | {:error, Error.t()}
  def recreate(
        conn,
        container_identifier,
        job_name,
        job_id,
        ops \\ DockerOps,
        options \\ Application.get_env(:exdock_client, :recreation_readiness, [])
      )
      when is_binary(container_identifier) and is_atom(ops) do
    progress = &progress(job_id, job_name, &1)

    case Workflow.run(conn, container_identifier, ops, progress, options) do
      {:ok, new_id, cleanup_result} ->
        finish(new_id, cleanup_result)

      {:error, operation, reason, rollback_errors} ->
        {:error, Failure.build(operation, reason, rollback_errors)}
    end
  end

  defp progress(nil, _job_name, _message), do: :ok

  defp progress(job_id, job_name, message) do
    ClientLib.send_job_update(Messages.Update.new(job_id, job_name, message))
  end

  defp finish(new_id, {:ok, original_name}) do
    Logger.info("OK | Recreated container [#{original_name}]")
    {:ok, new_id}
  end

  defp finish(new_id, {:cleanup_failed, original_name, temporary_name, reason}) do
    warning =
      "Container [#{original_name}] was recreated, but cleanup of " <>
        "[#{temporary_name}] failed: #{Utils.error_message(reason)}"

    Logger.warning(warning)
    {:ok, %{id: new_id, warning: warning}}
  end
end
