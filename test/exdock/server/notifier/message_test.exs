defmodule Exdock.Server.Notifier.MessageTest do
  use ExUnit.Case, async: true

  alias Exdock.Datetime
  alias Exdock.Server.Notifier.Message
  alias Exdock.Domain.{Repository, TagInfo}

  test "formats job errors and container transitions" do
    assert Message.job_error(:image_pull, "job-1", true, "node-a", :registry_unavailable) ==
             ~s(job_name=image_pull job_id=job-1 automated=true node=node-a error="registry_unavailable")

    assert Message.container_status("node-a", "api", :high, :running, :stopped) ==
             "node=node-a container=api priority=high changed from old=running new=stopped"
  end

  test "formats repository releases in the configured timezone" do
    released_at = ~U[2026-01-02 03:04:05Z]

    release = %Repository.Release{
      name: "example",
      version: "1.2.3",
      release_url: "https://example.com/releases/1.2.3",
      time_released: released_at
    }

    assert Message.repository_release(release) ==
             ~s(name=example version=1.2.3 release_url=https://example.com/releases/1.2.3 time_released="#{Datetime.utc_to_timezone(released_at)}")
  end

  test "formats registry tags in the configured timezone" do
    published_at = ~U[2026-02-03 04:05:06Z]

    tag = %TagInfo{
      tag: "example/app:latest",
      platform: "linux/amd64",
      latest_date: published_at,
      latest_digest: "sha256:deadbeef"
    }

    assert Message.image_tag(tag) ==
             ~s(tag=example/app:latest platform=linux/amd64 date="#{Datetime.utc_to_timezone(published_at)}" digest=sha256:deadbeef)
  end
end
