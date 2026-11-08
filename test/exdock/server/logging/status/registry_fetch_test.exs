defmodule Exdock.Server.Logging.Status.RegistryFetchTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Logging.Status
  alias Exdock.Server.Logging.Status.Lifecycle
  alias Exdock.Server.Logging.Status.RegistryFetch
  alias Exdock.Server.Logging.Status.TrackedJob
  alias Exdock.Server.Logging.Status.Utils

  @now ~U[2026-07-31 10:00:00Z]

  test "error updates still persist aggregate progress before logging the error" do
    status =
      %Status{}
      |> Utils.set_job_data(
        :registry_fetch,
        "job-1",
        TrackedJob.new(
          [:local],
          %{
            image_requests: [
              %{tag: "example/app:latest", platform: "linux/amd64"}
            ],
            tags_fetched: 0,
            tags_to_fetch: 1
          },
          {:ok, :requested}
        )
      )

    lifecycle =
      Lifecycle.updated(
        :registry_fetch,
        "job-1",
        :local,
        "example/app:latest",
        :failed,
        @now
      )

    status = RegistryFetch.update(status, lifecycle)

    assert %{
             data: %{tags_fetched: 1, tags_to_fetch: 1},
             state: {:ok, :requested}
           } = Utils.get_job_data(status, :registry_fetch, "job-1")

    assert status.latest_job_message == "1 of 1 images processed"
    assert [{_time, "fetch registry [example/app:latest]: :failed"}] = status.errors
  end

  test "terminal registry failures are added to the detailed error log" do
    status =
      %Status{}
      |> RegistryFetch.result(
        Lifecycle.finished(
          :registry_fetch,
          "job-1",
          :local,
          nil,
          {:local_job_failed, :error, "regc failed"},
          @now
        )
      )

    assert status.latest_job_message_is_error

    assert [{_time, "fetch registry: {:local_job_failed, :error, \"regc failed\"}"}] =
             status.errors
  end
end
