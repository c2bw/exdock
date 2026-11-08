defmodule Exdock.Database.ImageTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database.Image
  alias Exdock.Database.Image.Record
  alias Exdock.Database.Image.Row
  alias Exdock.Repo
  alias Exdock.TestFixtures.DomainImage, as: ImageFixture

  test "stores runtime node and tags in database format" do
    image = image(id: "sha256:stored", tags: ["example/app:latest", "example/app:stable"])

    assert {:ok, %Record{node: "node", tags: ["example/app:latest", "example/app:stable"]}} = Image.insert(image)

    assert %Row{
             node: "node",
             tags: "example/app:latest,example/app:stable",
             image_key: "node:sha256:stored"
           } = Repo.get_by(Row, node: "node", id: "sha256:stored")
  end

  test "round-trips an empty tag list without producing a blank tag" do
    image = image(id: "sha256:image-id", tags: [])

    assert {:ok, %Record{node: "node", tags: []}} = Image.insert(image)
    assert %Record{node: "node", tags: []} = Image.by_node_and_id("node", "sha256:image-id")
  end

  test "validates and upserts image batches" do
    images = [
      image(id: "sha256:batch-a", tags: ["example/a:latest"]),
      image(id: "sha256:batch-b", tags: [])
    ]

    assert :ok = Image.insert_all(images)
    assert %Record{tags: ["example/a:latest"]} = Image.by_node_and_id("node", "sha256:batch-a")
    assert %Record{tags: []} = Image.by_node_and_id("node", "sha256:batch-b")

    assert {:error, %Ecto.Changeset{valid?: false}} =
             Image.insert_all([image(id: nil)])
  end

  test "bulk upserts retain changes to repository digests" do
    original = %{image(id: "sha256:multi") | repo_digests: ["example/first@sha256:first"]}
    assert :ok = Image.insert_all([original])
    references = ["example/first@sha256:first", "example/second@sha256:second"]
    changed = %{original | repo_digests: references}
    refute Image.same?(original, changed)
    assert :ok = Image.insert_all([changed])
    assert %Record{repo_digests: ^references} = Image.by_node_and_id("node", original.id)
  end

  test "loads images by node and digest using application-facing node/tag types" do
    first = image(id: "sha256:first", tags: ["example/app:latest"], digest: "sha256:shared")
    second = image(id: "sha256:second", tags: ["example/db:latest"], digest: "sha256:other")
    other_node = image(node: "other_node", id: "sha256:third", tags: ["example/cache:latest"], digest: "sha256:shared")

    assert {:ok, %Record{}} = Image.insert(first)
    assert {:ok, %Record{}} = Image.insert(second)
    assert {:ok, %Record{}} = Image.insert(other_node)

    assert images = Image.by_node("node")
    assert images |> Enum.map(& &1.id) |> Enum.sort() == ["sha256:first", "sha256:second"]
    assert %Record{node: "node", id: "sha256:first"} = Image.by_node_and_digest("node", "sha256:shared")
    assert Image.by_node_and_digest("node", "missing") == nil
  end

  test "loads one deterministic image when a node has multiple blank digests" do
    second = image(id: "sha256:second", tags: [], digest: "")
    first = image(id: "sha256:first", tags: [], digest: "")
    other_node = image(node: "other_node", id: "sha256:other", tags: [], digest: "")

    assert {:ok, %Record{}} = Image.insert(second)
    assert {:ok, %Record{}} = Image.insert(first)
    assert {:ok, %Record{}} = Image.insert(other_node)

    assert %Record{node: "node", id: "sha256:first", digest: ""} =
             Image.by_node_and_digest("node", "")
  end

  test "loads images using stored string node keys" do
    first = image(id: "sha256:first", tags: ["example/app:latest"], digest: "sha256:shared")
    second = image(id: "sha256:second", tags: ["example/db:latest"], digest: "sha256:other")

    assert {:ok, %Record{}} = Image.insert(first)
    assert {:ok, %Record{}} = Image.insert(second)

    assert images = Image.by_node("node")
    assert images |> Enum.map(& &1.id) |> Enum.sort() == ["sha256:first", "sha256:second"]
    assert %Record{node: "node", id: "sha256:first"} = Image.by_node_and_id("node", "sha256:first")
    assert %Record{node: "node", id: "sha256:first"} = Image.by_node_and_digest("node", "sha256:shared")
  end

  test "rejects invalid stored node keys in lookup helpers" do
    assert_raise ArgumentError, fn -> Image.by_node("bad node") end
    assert_raise ArgumentError, fn -> Image.by_node_and_id("bad node", "sha256:image-id") end
    assert_raise ArgumentError, fn -> Image.by_node_and_digest("bad node", "sha256:image-id") end
  end

  test "nodeset_update removes images missing from the latest node snapshot" do
    keep = image(id: "sha256:keep")
    remove = image(id: "sha256:remove")

    assert {:ok, %Record{}} = Image.insert(keep)
    assert {:ok, %Record{}} = Image.insert(remove)

    assert {1, nil} = Image.nodeset_update("node", ["sha256:keep"])
    assert %Record{id: "sha256:keep"} = Image.by_node_and_id("node", "sha256:keep")
    assert Image.by_node_and_id("node", "sha256:remove") == nil
  end

  test "nodeset_update accepts stored string node keys" do
    keep = image(id: "sha256:keep")
    remove = image(id: "sha256:remove")

    assert {:ok, %Record{}} = Image.insert(keep)
    assert {:ok, %Record{}} = Image.insert(remove)

    assert {1, nil} = Image.nodeset_update("node", ["sha256:keep"])
    assert %Record{id: "sha256:keep"} = Image.by_node_and_id("node", "sha256:keep")
    assert Image.by_node_and_id("node", "sha256:remove") == nil
  end

  defp image(opts) do
    ImageFixture.build(Keyword.merge([name: "example/app", tags: ["example/app:latest"]], opts))
    |> Image.new()
  end
end
