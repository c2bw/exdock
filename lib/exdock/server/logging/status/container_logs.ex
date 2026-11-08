defmodule Exdock.Server.Logging.Status.ContainerLogs do
  use Exdock.Server.Logging.Status.ContainerAction,
    action_label: "Container Logs",
    error_action: "fetch container logs"

  alias Exdock.Server.Logging.Status.ContainerAction
  alias Exdock.Server.Logging.Status.Lifecycle
  alias Exdock.Server.Logging.Status.Utils

  @impl true
  def result(
        status,
        %Lifecycle{job_id: job_id, node: node, data: data, error: error, occurred_at: occurred_at}
      ) do
    container_name = tracked_container_name(status, job_id, data)

    ContainerAction.result(
      status,
      "Container Logs",
      "fetch container logs",
      node,
      container_name,
      error,
      occurred_at
    )
  end

  defp tracked_container_name(status, job_id, fallback) do
    case Utils.get_job_data(status, :container_logs, job_id) do
      %{data: name} when is_binary(name) -> name
      _ -> fallback
    end
  end
end
