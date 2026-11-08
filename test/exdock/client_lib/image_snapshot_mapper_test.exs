defmodule Exdock.ClientLib.Image.SnapshotMapperTest do
  use ExUnit.Case, async: true

  alias DockerEngineAPI.Model
  alias Exdock.ClientLib.Image.SnapshotMapper
  alias Exdock.Protocol.ImageReference

  test "normalizes tags without confusing registry ports for tag separators" do
    assert ImageReference.ensure_tag("registry.example:5000/team/app") ==
             "registry.example:5000/team/app:latest"

    assert ImageReference.ensure_tag("registry.example:5000/team/app:v1") ==
             "registry.example:5000/team/app:v1"
  end

  test "maps image summaries with registry ports and digests" do
    summary = %Model.ImageSummary{
      :RepoDigests => ["registry.example:5000/team/app@sha256:abc"],
      :RepoTags => ["registry.example:5000/team/app:latest"],
      :Id => "sha256:image",
      :Size => 2_000,
      :SharedSize => 500,
      :Created => 1_767_225_600
    }

    assert {:ok, snapshot} = SnapshotMapper.map(summary, summary."SharedSize")
    assert snapshot.name == "registry.example:5000/team/app"
    assert snapshot.digest == "sha256:abc"
    assert snapshot.tags == ["registry.example:5000/team/app:latest"]
    assert snapshot.size == 2_000
    assert snapshot.shared_size == 500
  end

  test "falls back to tags when an image has no repository digest" do
    summary = %Model.ImageSummary{
      :RepoDigests => [],
      :RepoTags => ["docker.io/library/alpine:latest"],
      :Id => "sha256:alpine",
      :Size => 1_000,
      :SharedSize => 0,
      :Created => "2026-01-01T00:00:00Z"
    }

    assert {:ok, snapshot} = SnapshotMapper.map(summary, 0)
    assert snapshot.name == "docker.io/library/alpine"
    assert snapshot.digest == ""
  end

  test "keeps untagged images identifiable by ID from inspect and summary responses" do
    id = "sha256:" <> String.duplicate("a", 64)

    for module <- [Model.ImageInspect, Model.ImageSummary], empty <- [[], nil] do
      source = struct!(module, RepoTags: empty, RepoDigests: empty, Id: id, Size: 1000, Created: 0)
      assert {:ok, snapshot} = SnapshotMapper.map(source, 0)
      assert snapshot.id == id
      assert snapshot.name == id
      assert snapshot.tags == []
      assert snapshot.digest == ""
      assert {:ok, ^snapshot} = snapshot |> Exdock.Protocol.Snapshot.Image.to_wire() |> Exdock.Protocol.Snapshot.Image.from_wire()
    end
  end

  test "image IDs do not become registry references or collide as metadata keys" do
    for id <- [String.duplicate("a", 64), "sha256:" <> String.duplicate("a", 64), "sha256:" <> String.duplicate("b", 64)] do
      assert ImageReference.image_id?(id)
      assert ImageReference.ensure_tag(id) == id
      assert ImageReference.truncate_tag(id) == id
      assert ImageReference.registry_url(id) == ""
      assert ImageReference.repository_url(id) == ""
      assert ImageReference.categorize_registry(id) == "Local image"
    end

    refute ImageReference.image_id?("sha256:ordinary-tag")
    refute ImageReference.image_id?("registry.example/app@sha256:" <> String.duplicate("a", 64))
  end

  test "maps dangling Docker placeholders as untagged images without logging errors" do
    id = "sha256:5076540d8e7eac46b6af2e4b5473dd527bfdf9a20b559871efbb24df9650ada9"

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        for module <- [Model.ImageInspect, Model.ImageSummary],
            tags <- [nil, [], [""], ["<none>:<none>"], [nil, " ", "<none>"]],
            digests <- [nil, [], [""], ["<none>@<none>"]] do
          source = struct!(module, RepoTags: tags, RepoDigests: digests, Id: id, Size: 1000, Created: 0)
          assert {:ok, snapshot} = SnapshotMapper.map(source, 0)
          assert snapshot.id == id
          assert snapshot.name == id
          assert snapshot.tags == []
          assert snapshot.repo_digests == []
          assert snapshot.digest == ""
        end
      end)

    assert log == ""
  end

  test "missing-reference placeholders do not hide valid repository references" do
    source = %Model.ImageInspect{
      Id: "sha256:image",
      RepoTags: ["", "<none>:<none>", "example/app:latest"],
      RepoDigests: ["<none>@<none>", "example/app@sha256:abc"],
      Size: 1000,
      Created: 0
    }

    assert {:ok, snapshot} = SnapshotMapper.map(source, 0)
    assert snapshot.name == "example/app"
    assert snapshot.tags == ["example/app:latest"]
    assert snapshot.repo_digests == ["example/app@sha256:abc"]
    assert snapshot.digest == "sha256:abc"
  end

  test "preserves every repository digest across wire encoding and compares the matching repository" do
    references = ["example/first@sha256:first", "example/second@sha256:second", "example/second@sha256:alternate"]

    source = %Model.ImageInspect{
      Id: "sha256:image",
      RepoTags: ["example/first:latest", "example/second:latest"],
      RepoDigests: references,
      Size: 1000,
      Created: 0
    }

    assert {:ok, snapshot} = SnapshotMapper.map(source, 0)
    assert snapshot.repo_digests == references
    assert {:ok, ^snapshot} = snapshot |> Exdock.Protocol.Snapshot.Image.to_wire() |> Exdock.Protocol.Snapshot.Image.from_wire()
    image = Exdock.Domain.Image.from_client(snapshot, "node", nil, true)
    now = DateTime.utc_now()

    for digest <- ["sha256:second", "sha256:alternate"] do
      tag = Exdock.Domain.TagInfo.new("docker.io/example/second:latest", "linux/amd64", digest, now, now)
      assert Exdock.Domain.Container.Core.ImageData.new(tag, image, true).status == :updated
    end

    tag = Exdock.Domain.TagInfo.new("example/second:latest", "linux/amd64", "sha256:first", now, now)
    assert Exdock.Domain.Container.Core.ImageData.new(tag, image, true).status == :outdated
    assert Enum.sort(Exdock.Domain.Image.all_digests(image)) == ["sha256:alternate", "sha256:first", "sha256:second"]
  end

  test "accepts legacy snapshots and rejects malformed repository digests" do
    snapshot = %Exdock.Protocol.Snapshot.Image{
      id: "id",
      name: "example/app",
      tags: [],
      digest: "sha256:old",
      size: 100,
      shared_size: 0,
      build_date: DateTime.from_unix!(0)
    }

    wire = Exdock.Protocol.Snapshot.Image.to_wire(snapshot)
    assert {:ok, ^snapshot} = Exdock.Protocol.Snapshot.Image.from_wire(Map.delete(wire, "repo_digests"))

    for invalid <- [nil, "invalid", [42], [%{}]] do
      assert {:error, :invalid_image_snapshot} = Exdock.Protocol.Snapshot.Image.from_wire(Map.put(wire, "repo_digests", invalid))
    end

    image = Exdock.Domain.Image.from_client(snapshot, "node", nil, true)
    assert Exdock.Domain.Image.digests_for_tag(image, "example/app:latest") == ["sha256:old"]
  end

  test "rejects images without any identity" do
    summary = %Model.ImageSummary{RepoTags: [], RepoDigests: [], Id: nil, Size: 1000, Created: 0}
    assert SnapshotMapper.map(summary, 0) == {:error, "image has empty digest and tags"}
  end
end
