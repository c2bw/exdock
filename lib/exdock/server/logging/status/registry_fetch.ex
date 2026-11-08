defmodule Exdock.Server.Logging.Status.RegistryFetch do
  use Exdock.Server.Logging.Status.JobBehaviour
  alias Exdock.Server.Logging.Status.Lifecycle
  alias Exdock.Server.Logging.Status.Progress
  alias Exdock.Server.Logging.Status.Utils
  alias Exdock.Server.Jobs.Payload.RegistryFetch

  @job_name "Fetch Registry"
  @error_action "fetch registry"

  @impl true
  def data_init(%RegistryFetch{image_requests: image_requests}) do
    total_requests = count_requests(image_requests)

    %{
      image_requests: image_requests,
      tags_fetched: 0,
      tags_to_fetch: total_requests
    }
  end

  @impl true
  def log(%RegistryFetch{image_requests: image_requests}),
    do: {count_requests(image_requests), []}

  @impl true
  def add(status, %Lifecycle{data: %RegistryFetch{image_requests: image_requests}}) do
    status
    |> Utils.set_job_message(
      @job_name,
      initial_progress_message(image_requests)
    )
  end

  @impl true
  def update(
        status,
        %Lifecycle{job_name: job_name, job_id: job_id, data: data, error: error, occurred_at: occurred_at}
      ) do
    # Keep aggregate progress persisted even when this chunk errors so dashboards
    # always reflect work done before the error log entry.
    status
    |> Progress.bump(job_name, job_id, :tags_fetched, @job_name, &progress_message/1)
    |> Progress.maybe_log_error(data, error, occurred_at, &fetch_error_message/2)
  end

  @impl true
  def result(status, %Lifecycle{error: nil}) do
    status |> Utils.set_job_message(@job_name, "OK")
  end

  def result(status, %Lifecycle{error: error, occurred_at: occurred_at}) do
    status
    |> Utils.set_job_message(@job_name, "failed: #{inspect(error)}", true)
    |> Utils.add_entry_to_errors_log("#{@error_action}: #{format_error(error)}", occurred_at)
  end

  @impl true
  def dash_key(job_id, _location, _data), do: job_id

  @impl true
  def dash_data(data), do: %{fetched: data.tags_fetched, total: data.tags_to_fetch}

  defp progress_message(%{tags_fetched: fetched, tags_to_fetch: total}),
    do: format_fetch_progress(fetched, total)

  defp initial_progress_message(image_requests),
    do: format_fetch_progress(0, count_requests(image_requests))

  defp format_fetch_progress(fetched, total), do: "#{fetched} of #{total} images processed"

  defp count_requests(image_requests), do: Enum.count(image_requests)

  defp fetch_error_message(data, error), do: "#{@error_action} [#{data}]: #{format_error(error)}"

  defp format_error(%{__exception__: true} = error), do: Exception.message(error)
  defp format_error(error), do: inspect(error)
end
