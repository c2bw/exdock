defmodule Exdock.Domain.TagInfoTest do
  use Exdock.DataCase, async: false

  alias Exdock.Server.State.Storage.Persistence.TagInfo, as: TagInfoPersistence
  alias Exdock.Domain.TagInfo

  @image_tag "registry.example/app:latest"

  test "insert/1 and load/1 round-trip registry tag information" do
    tag_info =
      TagInfo.new(
        @image_tag,
        "linux/amd64",
        "sha256:digest",
        ~U[2026-06-30 15:43:22.987654Z],
        ~U[2026-06-30 16:00:00.123456Z]
      )

    assert {:ok, _stored} = TagInfoPersistence.insert(tag_info)

    assert %TagInfo{
             tag: @image_tag,
             platform: "linux/amd64",
             latest_digest: "sha256:digest",
             latest_date: ~U[2026-06-30 15:43:22Z],
             check_date: ~U[2026-06-30 16:00:00Z]
           } = TagInfoPersistence.load(@image_tag, "linux/amd64")
  end

  test "load_all/0 keeps separate rows for the same tag on different platforms" do
    assert {:ok, _stored} =
             "registry.example/app:stable"
             |> TagInfo.default("linux/amd64")
             |> TagInfoPersistence.insert()

    assert {:ok, _stored} =
             "registry.example/app:stable"
             |> TagInfo.default("linux/arm64")
             |> TagInfoPersistence.insert()

    assert TagInfoPersistence.load_all()
           |> MapSet.new(&{&1.tag, &1.platform}) ==
             MapSet.new([
               {"registry.example/app:stable", "linux/amd64"},
               {"registry.example/app:stable", "linux/arm64"}
             ])
  end

  test "load/1 returns nil for unknown tags" do
    assert TagInfoPersistence.load("registry.example/missing:latest", "linux/amd64") == nil
  end
end
