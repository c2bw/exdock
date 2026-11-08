defmodule Exdock.Server.Logging.Status.ReleasesFetch do
  use Exdock.Server.Logging.Status.JobBehaviour
  alias Exdock.Server.Logging.Status.Lifecycle
  alias Exdock.Server.Logging.Status.Progress
  alias Exdock.Server.Logging.Status.Utils
  alias Exdock.Server.Jobs.Payload.ReleasesFetch
  alias Exdock.Domain.Repository.Release

  @job_name "Fetch Releases"

  @impl true
  def data_init(%ReleasesFetch{repositories: repositories, releases_list: releases_list}) do
    %{
      repositories: repositories,
      releases_list: releases_list,
      fetched: 0,
      to_fetch: total_repositories_to_fetch(repositories)
    }
  end

  @impl true
  def log(%ReleasesFetch{repositories: repositories}), do: {release_fetch_log_payload(repositories), []}

  @impl true
  def add(status, %Lifecycle{data: %ReleasesFetch{repositories: repositories}}) do
    status
    |> Utils.set_job_message(@job_name, format_fetch_progress(0, total_repositories_to_fetch(repositories)))
  end

  @impl true
  def update(
        status,
        %Lifecycle{job_name: job_name, job_id: job_id, data: data, error: error, occurred_at: occurred_at}
      ) do
    status
    |> Progress.bump(job_name, job_id, :fetched, @job_name, &progress_message/1)
    |> Progress.maybe_log_error(data, error, occurred_at, &fetch_error_message/2)
  end

  @impl true
  def result(status, %Lifecycle{data: {:done, _fetched_releases}, error: nil}) do
    status
    |> Utils.set_job_message(@job_name, "OK")
  end

  def result(status, %Lifecycle{error: error}) do
    status
    |> Utils.set_job_message(@job_name, "failed: #{inspect(error)}", true)
  end

  @impl true
  def dash_key(job_id, _location, _data), do: job_id

  @impl true
  def dash_data(data), do: %{fetched: data.fetched, total: data.to_fetch}

  @doc false
  @spec detect_new_releases([Release.t()], [Release.t()]) :: [Release.t()]
  def detect_new_releases(fetched_releases, baseline_releases) do
    Enum.reject(fetched_releases, &release_in_baseline?(&1, baseline_releases))
  end

  @doc false
  @spec latest_release_by_repository([Release.t()]) :: %{String.t() => Release.t()}
  def latest_release_by_repository(releases) do
    # The notification layer wants one message per repository. When several new
    # versions arrive together, keep the newest release so users see the most
    # relevant update instead of a burst of older versions.
    releases
    |> Enum.group_by(& &1.repository)
    |> Map.new(fn {repository, releases} -> {repository, latest_release(releases)} end)
  end

  defp progress_message(%{fetched: fetched, to_fetch: total}), do: format_fetch_progress(fetched, total)

  defp fetch_error_message(data, error), do: "fetch releases [#{data}]: #{inspect(error)}"

  defp total_repositories_to_fetch(repositories), do: Enum.count(repositories)

  defp release_fetch_log_payload(repositories) do
    %{repos_count: total_repositories_to_fetch(repositories), new_releases_count: 0}
  end

  @doc false
  @impl true
  @spec completion_log_options(map(), Lifecycle.t()) :: keyword()
  def completion_log_options(
        status,
        %Lifecycle{
          job_name: job_name,
          job_id: job_id,
          data: {:done, fetched_releases}
        }
      ) do
    job_data = Utils.get_job_data(status, job_name, job_id)
    new_releases = detect_new_releases(fetched_releases, job_data.data.releases_list)

    # Preserve the original progress log row and patch only the final count.
    [
      lazy: true,
      change_message_data: {:new_releases_count, Enum.count(new_releases)}
    ]
  end

  @impl true
  def result_effects(
        status,
        %Lifecycle{
          job_name: job_name,
          job_id: job_id,
          data: {:done, fetched_releases},
          error: nil
        }
      ) do
    baseline_releases =
      status
      |> Utils.get_job_data(job_name, job_id)
      |> then(& &1.data.releases_list)

    fetched_releases
    |> detect_new_releases(baseline_releases)
    |> latest_release_by_repository()
    |> Map.values()
    |> Enum.map(&{:notify_repository_release, &1})
  end

  def result_effects(_status, %Lifecycle{}), do: []

  defp release_in_baseline?(release, baseline_releases) do
    Enum.any?(baseline_releases, &Release.same_version(release, &1))
  end

  defp latest_release([release | releases]) do
    Enum.reduce(releases, release, &newer_release/2)
  end

  defp newer_release(release, latest_release) do
    case DateTime.compare(latest_release.time_released, release.time_released) do
      :gt -> latest_release
      _ -> release
    end
  end

  defp format_fetch_progress(fetched, total), do: "#{fetched} of #{total} repositories processed"
end
