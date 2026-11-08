defmodule Exdock.AgentRuntime.Executor do
  @moduledoc """
  Allowlisted command dispatcher for Docker work on an Exdock agent.

  Every command shape is matched explicitly. Adding an agent capability requires
  adding a protocol command and a clause here; arbitrary function dispatch is
  intentionally impossible.
  """

  alias Exdock.ClientLib.Jobs
  alias Exdock.Protocol.Command

  alias Exdock.Protocol.Command.{
    ContainerLogs,
    ContainerRecreate,
    ContainerResources,
    ContainerRestart,
    ContainerStart,
    ContainerStop,
    ImageDelete,
    ImagePull,
    NodeRefresh
  }

  @compile {:no_warn_undefined, Exdock.ClientLib.Jobs}
  @compile {:no_warn_undefined, {Exdock.ClientLib.Jobs.Context, :runtime, 0}}

  @type execution_result :: {:ok, term()} | {:error, term(), term()}

  @spec execute(map() | {:exdock_execution, map(), term()}) :: execution_result()
  def execute({:exdock_execution, command, context}) when is_map(command),
    do: execute(command, context)

  def execute(command) when is_map(command),
    do: execute(command, Exdock.ClientLib.Jobs.Context.runtime())

  defp execute(command, context) do
    case Command.decode(command) do
      {:ok, decoded} -> execute_decoded(decoded, context)
      {:error, reason} -> {:error, reason, nil}
    end
  end

  defp execute_decoded(%NodeRefresh{id: id, retrieve_resources: retrieve_resources}, context),
    do: Jobs.node_refresh(id, [retrieve_resources: retrieve_resources], context)

  defp execute_decoded(%ContainerRecreate{id: id, container_id: container_id, pull_image: pull_image}, context),
    do: Jobs.container_recreate(id, container_id, pull_image, context)

  defp execute_decoded(%ImageDelete{id: id, image_id: image_id}, context),
    do: Jobs.image_delete(id, image_id, context)

  defp execute_decoded(%ImagePull{id: id, image_tag: tag}, context),
    do: Jobs.image_pull(id, tag, context)

  defp execute_decoded(%ContainerStart{id: id, container_id: container_id}, context),
    do: Jobs.container_start(id, container_id, context)

  defp execute_decoded(%ContainerStop{id: id, container_id: container_id}, context),
    do: Jobs.container_stop(id, container_id, context)

  defp execute_decoded(%ContainerRestart{id: id, container_id: container_id}, context),
    do: Jobs.container_restart(id, container_id, context)

  defp execute_decoded(%ContainerLogs{id: id, container_id: container_id, opts: opts}, context),
    do: Jobs.container_logs(id, container_id, opts, context)

  defp execute_decoded(%ContainerResources{id: id, container_id: container_id}, context),
    do: Jobs.container_resources(id, container_id, context)
end
