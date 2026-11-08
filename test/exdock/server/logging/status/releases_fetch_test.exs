defmodule Exdock.Server.Logging.Status.ReleasesFetchTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Logging.Status
  alias Exdock.Server.Logging.Status.Lifecycle
  alias Exdock.Server.Logging.Status.ReleasesFetch
  alias Exdock.Server.Logging.Status.TrackedJob
  alias Exdock.Server.Logging.Status.Utils
  alias Exdock.Domain.Repository.Release

  @now ~U[2026-07-31 10:00:00Z]

  test "detect_new_releases ignores releases already present in the initial snapshot" do
    known = release("example/app", "v1.0.0", ~U[2026-06-01 00:00:00Z])
    changed_description = release("example/app", "v1.0.0", ~U[2026-06-02 00:00:00Z])
    new = release("example/app", "v2.0.0", ~U[2026-06-03 00:00:00Z])

    assert ReleasesFetch.detect_new_releases([changed_description, new], [known]) == [new]
  end

  test "latest_release_by_repository keeps only the newest new release per repository" do
    old = release("example/app", "v1.0.0", ~U[2026-06-01 00:00:00Z])
    new = release("example/app", "v2.0.0", ~U[2026-06-03 00:00:00Z])
    other = release("example/db", "v1.0.0", ~U[2026-06-02 00:00:00Z])

    assert ReleasesFetch.latest_release_by_repository([old, new, other]) == %{
             "example/app" => new,
             "example/db" => other
           }
  end

  test "error updates still persist aggregate progress before logging the error" do
    status =
      %Status{}
      |> Utils.set_job_data(:releases_fetch, "job-1", initial_job_data(["example/app"], []))

    lifecycle = Lifecycle.updated(:releases_fetch, "job-1", :local, "example/app", :failed, @now)
    status = ReleasesFetch.update(status, lifecycle)

    assert %{
             data: %{fetched: 1, to_fetch: 1},
             state: {:ok, :requested}
           } = Utils.get_job_data(status, :releases_fetch, "job-1")

    assert status.latest_job_message == "1 of 1 repositories processed"
    assert [{_time, "fetch releases [example/app]: :failed"}] = status.errors
  end

  test "new release notifications are returned as effects" do
    known = release("example/app", "v1.0.0", ~U[2026-06-01 00:00:00Z])
    newest = release("example/app", "v2.0.0", ~U[2026-06-03 00:00:00Z])

    status =
      %Status{}
      |> Utils.set_job_data(
        :releases_fetch,
        "job-1",
        initial_job_data(["example/app"], [known])
      )

    lifecycle =
      Lifecycle.finished(
        :releases_fetch,
        "job-1",
        :local,
        {:done, [known, newest]},
        nil,
        @now
      )

    assert [{:notify_repository_release, ^newest}] =
             ReleasesFetch.result_effects(status, lifecycle)
  end

  defp release(repository, version, time_released) do
    Release.new(:github, repository, repository, version, "#{repository}/releases/#{version}", "Notes", time_released)
  end

  defp initial_job_data(repositories, releases_list) do
    TrackedJob.new(
      [:local],
      %{repositories: repositories, releases_list: releases_list, fetched: 0, to_fetch: Enum.count(repositories)},
      {:ok, :requested}
    )
  end
end
