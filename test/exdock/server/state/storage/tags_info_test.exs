defmodule Exdock.Server.State.Storage.TagsInfoTest do
  use Exdock.DataCase, async: false

  alias Exdock.Server.State
  alias Exdock.Server.State.Domains.Tags, as: TagsDomain
  alias Exdock.Server.State.Change.{Outcome, Plan}
  alias Exdock.Runtime.Mutation
  alias Exdock.Server.State.Storage.Persistence.TagInfo, as: TagInfoPersistence
  alias Exdock.Server.State.Storage.TagsInfo
  alias Exdock.Domain

  test "newer? only returns true for existing older tags" do
    old = tag_info("example/app:latest", ~U[2026-06-01 00:00:00Z])
    newer = tag_info("example/app:latest", ~U[2026-06-02 00:00:00Z])
    older = tag_info("example/app:latest", ~U[2026-05-31 00:00:00Z])

    tags = %TagsInfo{tags: %{{old.tag, old.platform} => old}}

    assert TagsInfo.newer?(tags, newer)
    refute TagsInfo.newer?(tags, older)
    refute TagsInfo.newer?(%TagsInfo{tags: %{}}, newer)
  end

  test "set/2 persists and caches tag metadata" do
    tag_info = tag_info("example/app:latest", ~U[2026-06-01 00:00:00Z])

    {:ok, tags} = TagsInfo.set(%TagsInfo{tags: %{}}, tag_info)

    assert TagsInfo.get(tags, tag_info.tag, tag_info.platform) == tag_info

    assert TagInfoPersistence.load(tag_info.tag, tag_info.platform).latest_digest ==
             tag_info.latest_digest
  end

  test "set/2 caches the same tag independently by platform" do
    amd64 =
      tag_info(
        "example/app:latest",
        ~U[2026-06-01 00:00:00Z],
        "sha256:amd64",
        "linux/amd64"
      )

    arm64 =
      tag_info(
        "example/app:latest",
        ~U[2026-06-02 00:00:00Z],
        "sha256:arm64",
        "linux/arm64"
      )

    {:ok, tags} = TagsInfo.set(%TagsInfo{tags: %{}}, amd64)
    {:ok, tags} = TagsInfo.set(tags, arm64)

    assert TagsInfo.get(tags, amd64.tag, amd64.platform) == amd64
    assert TagsInfo.get(tags, arm64.tag, arm64.platform) == arm64
  end

  test "change ignores older observations within a batch" do
    older = tag_info("example/app:latest", ~U[2026-06-01 00:00:00Z], "sha256:old")
    newer = tag_info("example/app:latest", ~U[2026-06-02 00:00:00Z], "sha256:new")
    older = %{older | check_date: ~U[2026-06-01 00:00:00Z]}
    newer = %{newer | check_date: ~U[2026-06-02 00:00:00Z]}
    state = %State{tags: %TagsInfo{tags: %{}}}
    payload = %Mutation{domain: :tags, action: :tags_info, data: [newer, older]}

    assert {:ok, %TagsInfo{} = tags, []} =
             TagsInfo.apply_updates(state.tags, payload.data)

    assert %Domain.TagInfo{latest_digest: "sha256:new"} =
             TagsInfo.get(tags, "example/app:latest", "linux/amd64")
  end

  test "domain changes return tag notifications as explicit effects" do
    old = tag_info("example/app:latest", ~U[2026-06-01 00:00:00Z], "sha256:old")
    newer = tag_info("example/app:latest", ~U[2026-06-02 00:00:00Z], "sha256:new")
    state = %State{tags: %TagsInfo{tags: %{{old.tag, old.platform} => old}}}
    assert {:ok, payload} = Mutation.tags_info([newer])

    assert %Outcome{
             state: %State{tags: %TagsInfo{} = tags},
             broadcast_opts: [],
             effects: [{:notify_image_tag, ^newer}]
           } =
             TagsDomain.plan(state, payload) |> Plan.execute()

    assert TagsInfo.get(tags, newer.tag, newer.platform) == newer
  end

  test "late observations cannot overwrite newer memory or persisted metadata" do
    older = tag_info("example/app:latest", ~U[2026-06-01 00:00:00Z], "sha256:old")
    older = %{older | check_date: ~U[2026-06-01 01:00:00Z]}
    newer = %{older | latest_digest: "sha256:new", latest_date: ~U[2026-06-02 00:00:00Z], check_date: ~U[2026-06-02 01:00:00Z]}
    {:ok, tags, []} = TagsInfo.apply_updates(%TagsInfo{tags: %{}}, [newer])
    assert {:ok, ^tags, []} = TagsInfo.apply_updates(tags, [older])
    assert {:ok, ^tags} = TagsInfo.set(tags, older)
    assert TagInfoPersistence.load(newer.tag, newer.platform).latest_digest == newer.latest_digest
    assert TagsInfo.get(tags, newer.tag, newer.platform) == newer
  end

  test "newer observations may legitimately point to older images" do
    original = tag_info("example/app:latest", ~U[2026-06-02 00:00:00Z], "sha256:new")
    original = %{original | check_date: ~U[2026-06-02 01:00:00Z]}

    rollback = %{
      original
      | latest_digest: "sha256:rollback",
        latest_date: ~U[2026-06-01 00:00:00Z],
        check_date: ~U[2026-06-03 01:00:00Z]
    }

    {:ok, tags} = TagsInfo.set(%TagsInfo{tags: %{}}, original)
    assert {:ok, updated, []} = TagsInfo.apply_updates(tags, [rollback])
    assert TagsInfo.get(updated, rollback.tag, rollback.platform) == rollback
    assert TagInfoPersistence.load(rollback.tag, rollback.platform).latest_digest == "sha256:rollback"
  end

  test "undated defaults cannot replace observed tags and equal timestamps preserve payload order" do
    default = Domain.TagInfo.default("example/app:latest", "linux/amd64")
    observed = %{default | check_date: ~U[2026-06-03 01:00:00Z], latest_digest: "sha256:one"}
    equal_time = %{observed | latest_digest: "sha256:two"}
    {:ok, tags, []} = TagsInfo.apply_updates(%TagsInfo{tags: %{}}, [default, observed, default, equal_time])
    assert TagsInfo.get(tags, observed.tag, observed.platform) == equal_time
    assert TagInfoPersistence.load(observed.tag, observed.platform).latest_digest == "sha256:two"
    assert {:ok, ^tags} = TagsInfo.set(tags, default)
  end

  defp tag_info(
         tag,
         latest_date,
         digest \\ "sha256:digest",
         platform \\ "linux/amd64"
       ) do
    Domain.TagInfo.new(
      tag,
      platform,
      digest,
      latest_date,
      DateTime.utc_now()
    )
  end
end
