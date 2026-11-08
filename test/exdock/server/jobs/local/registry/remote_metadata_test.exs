defmodule Exdock.Server.Jobs.Local.Registry.RemoteMetadataTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.Local.Registry.RemoteMetadata
  alias Exdock.Domain.TagInfo

  test "fetches and truncates the creation date for a new tag" do
    owner = self()
    image_tag = "registry.example/team/app:latest"
    platform = "linux/amd64"

    assert {"sha256:new", ~U[2026-01-02 03:04:05Z]} =
             RemoteMetadata.fetch(
               image_tag,
               platform,
               nil,
               fn ^image_tag, ^platform -> "sha256:new" end,
               fn "registry.example/team/app@sha256:new", ^platform ->
                 send(owner, :creation_date_fetched)
                 ~U[2026-01-02 03:04:05.987654Z]
               end
             )

    assert_receive :creation_date_fetched
  end

  test "refreshes the creation date when the digest changes" do
    image_tag = "registry.example/team/app:latest"
    platform = "linux/amd64"
    previous_date = ~U[2025-01-02 03:04:05Z]
    previous = TagInfo.new(image_tag, platform, "sha256:old", previous_date, previous_date)

    assert {"sha256:new", ~U[2026-01-02 03:04:05Z]} =
             RemoteMetadata.fetch(
               image_tag,
               platform,
               previous,
               fn _image_tag, _platform -> "sha256:new" end,
               fn _image_tag, _platform -> ~U[2026-01-02 03:04:05.123456Z] end
             )
  end

  test "pins the creation lookup even when the tag changes between requests" do
    tag = "registry.example:5000/team/app:latest"
    now = ~U[2026-11-07 00:00:00Z]
    moved = ~U[2026-11-08 00:00:00Z]
    registry = start_supervised!({Agent, fn -> {"sha256:a", now} end})

    digest_lookup = fn ^tag, _platform ->
      Agent.get_and_update(registry, fn {digest, _} -> {digest, {"sha256:b", moved}} end)
    end

    date_lookup = fn reference, _platform ->
      case reference do
        "registry.example:5000/team/app@sha256:a" -> now
        ^tag -> Agent.get(registry, &elem(&1, 1))
      end
    end

    assert {"sha256:a", ^now} = RemoteMetadata.fetch(tag, "linux/amd64", nil, digest_lookup, date_lookup)
  end

  test "reuses the previous creation date when the digest is unchanged" do
    owner = self()
    image_tag = "registry.example/team/app:latest"
    platform = "linux/amd64"
    previous_date = ~U[2025-01-02 03:04:05Z]
    previous = TagInfo.new(image_tag, platform, "sha256:same", previous_date, previous_date)

    assert {"sha256:same", ^previous_date} =
             RemoteMetadata.fetch(
               image_tag,
               platform,
               previous,
               fn _image_tag, _platform -> "sha256:same" end,
               fn _image_tag, _platform ->
                 send(owner, :unexpected_creation_date_fetch)
                 ~U[2026-01-02 03:04:05Z]
               end
             )

    refute_receive :unexpected_creation_date_fetch
  end
end
