defmodule Exdock.Server.Logging.Status.NodeRefresh do
  use Exdock.Server.Logging.Status.JobBehaviour
  alias Exdock.Server.Jobs.Payload.NodeRefresh, as: NodeRefreshPayload
  alias Exdock.Server.Logging.Status
  alias Exdock.Server.Logging.Status.ContainerDifferences
  alias Exdock.Server.Logging.Status.Lifecycle
  alias Exdock.Server.Logging.Status.NodeRefresh.Progress
  alias Exdock.Server.Logging.Status.Utils

  @job_label "Refresh Nodes"
  @refresh_error_label "refresh node"

  @impl true
  def data_init(%NodeRefreshPayload{init_containers: containers_before}) do
    Progress.new(containers_before)
  end

  @impl true
  def log(%NodeRefreshPayload{log: log, log_opts: log_opts}) do
    if not is_nil(log), do: {log, log_opts}, else: false
  end

  @impl true
  def add(
        status,
        %Lifecycle{
          job_name: job_name,
          job_id: job_id,
          locations: locations,
          data: %NodeRefreshPayload{}
        }
      ) do
    status
    |> track_pending_refresh_nodes(job_name, job_id, locations)
    |> Utils.set_job_message(@job_label, "waiting for [#{Enum.count(locations)}] nodes")
  end

  @impl true
  def update(
        status,
        %Lifecycle{
          job_name: job_name,
          job_id: job_id,
          node: node,
          data: data,
          error: error,
          occurred_at: occurred_at
        }
      ) do
    {status, _remaining_nodes, _errored} =
      accumulate_node_response(status, job_name, job_id, node, data, error, occurred_at)

    status
    |> remove_node_dash_entry(job_name, node)
  end

  @impl true
  def result(status, %Lifecycle{error: nil}) do
    status
    |> Utils.set_job_message(@job_label, "OK")
  end

  def result(status, %Lifecycle{error: error}) when not is_nil(error) do
    # Leave the existing log untouched when the refresh finished with errors.
    status
  end

  @impl true
  def dash_key(_job_id, location, _data), do: location

  @impl true
  def dash_data(_data), do: nil

  @doc false
  @impl true
  @spec completion_log_options(Status.t(), Lifecycle.t()) :: keyword()
  def completion_log_options(
        status,
        %Lifecycle{job_name: job_name, job_id: job_id}
      ) do
    job_data = Utils.get_job_data(status, job_name, job_id)

    ContainerDifferences.calculate(
      job_data.data.containers_before,
      job_data.data.containers_response
    )
    |> build_container_delta_log_opts()
  end

  defp build_container_delta_log_opts(containers) do
    []
    |> maybe_unhide_when_container_changes(containers)
    |> Keyword.put(:lazy, true)
    |> Keyword.put(:change_message_data, {:containers, containers})
  end

  defp maybe_unhide_when_container_changes(opts, containers) do
    if container_changes_detected?(containers) do
      Keyword.put(opts, :unhide, true)
    else
      opts
    end
  end

  defp container_changes_detected?(containers) do
    Enum.any?(containers, fn {_node, changes} -> changes != [] end)
  end

  defp track_pending_refresh_nodes(status, job_name, job_id, locations) do
    job_data = Utils.get_job_data(status, job_name, job_id)
    updated_data = Progress.track(job_data.data, locations)

    Utils.set_job_data(status, job_name, job_id, %{job_data | data: updated_data})
  end

  defp accumulate_node_response(status, job_name, job_id, node, containers, error, occurred_at) do
    job_data = Utils.get_job_data(status, job_name, job_id)
    progress = Progress.restore(job_data.data, Map.get(job_data, :locations, []))
    {progress, outcome} = Progress.record_response(progress, node, containers, error)
    job_data = %{job_data | data: progress}

    {
      status
      |> Utils.set_job_data(job_name, job_id, job_data)
      |> Utils.set_job_message(
        @job_label,
        outcome.message,
        outcome.errored > 0
      )
      |> maybe_record_refresh_error(node, error, occurred_at),
      outcome.remaining_nodes,
      outcome.errored
    }
  end

  defp maybe_record_refresh_error(status, _node, nil, %DateTime{}), do: status

  defp maybe_record_refresh_error(status, node, error, %DateTime{} = occurred_at) do
    Utils.add_entry_to_errors_log(status, "#{@refresh_error_label} [#{node}]: #{inspect(error)}", occurred_at)
  end

  defp remove_node_dash_entry(status, job_name, node) do
    status
    |> Utils.get_dash_entry(job_name)
    |> Map.delete(node)
    |> then(&Utils.set_dash_entry(status, job_name, &1))
  end
end
