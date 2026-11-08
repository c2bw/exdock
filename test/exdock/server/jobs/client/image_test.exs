defmodule Exdock.Server.Jobs.Client.ImageTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Client.Image, as: ImageJobs
  alias Exdock.Server.Jobs.Payload.ImageAction
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage
  alias Exdock.Domain
  alias Exdock.TestFixtures.DomainImage, as: ImageFixture

  test "builds a remote delete detail for an existing image" do
    detail = ImageJobs.delete(state_with_images([image("image-id", tags: ["app:latest"])]), "node", "image-id")

    assert %Jobs.Detail{name: :image_delete, spec_list: [{%Jobs.Spec{} = spec, _id}]} = detail
    assert %Jobs.Spec.Remote{nodes: ["node"]} = spec.location
    assert spec.parameters == ["image-id"]
    assert spec.data == ImageAction.delete("node", "image-id", ["app:latest"])
  end

  test "returns no delete work when the image is missing" do
    assert ImageJobs.delete(state_with_images([]), "node", "missing") == nil
  end

  test "delete_unused skips in-use and locked images" do
    unused = image("unused")
    in_use = image("in-use", in_use: true)
    locked = image("locked", delete_lock: true)

    work = ImageJobs.delete_unused(state_with_images([unused, in_use, locked]), "node")

    assert [%Jobs.Detail{name: :image_delete, spec_list: [{%Jobs.Spec{parameters: ["unused"]}, _id}]}] = work
  end

  test "delete_unused returns an empty detail list when no image can be deleted" do
    work =
      state_with_images([
        image("in-use", in_use: true),
        image("locked", delete_lock: true)
      ])
      |> ImageJobs.delete_unused("node")

    assert work == []
  end

  test "pull returns one detail for a single requested image tag" do
    detail = ImageJobs.pull(%State{}, [%{node: "node", image_tag: "app:latest"}])

    assert %Jobs.Detail{name: :image_pull, spec_list: [{%Jobs.Spec{} = spec, _id}]} = detail
    assert %Jobs.Spec.Remote{nodes: ["node"]} = spec.location
    assert spec.parameters == ["app:latest"]
    assert spec.data == ImageAction.pull("node", "app:latest")
  end

  test "pull packages multiple image tags with aggregate log data" do
    package =
      ImageJobs.pull(%State{}, [
        %{node: "node_a", image_tag: "app:a"},
        %{node: "node_b", image_tag: "app:b"}
      ])

    assert %Jobs.Package{name: :image_pull, details: details, log_on_start: {2, ["app:a", "app:b"]}} = package
    assert Enum.map(details, & &1.name) == [:image_pull, :image_pull]
  end

  test "pull returns nil work for an empty request list" do
    assert ImageJobs.pull(%State{}, []) == nil
  end

  defp state_with_images(images) do
    storage =
      Storage.Cluster.new().storage
      |> Storage.Images.set_node("node", images)

    %State{cluster: %Storage.Cluster{storage: storage}}
  end

  defp image(id, opts \\ []) do
    ImageFixture.build(
      id: id,
      tags: Keyword.get(opts, :tags, []),
      in_use: Keyword.get(opts, :in_use, false),
      metadata: %Domain.Image.Metadata{},
      settings: %Domain.Image.Settings{delete_lock: Keyword.get(opts, :delete_lock, false)}
    )
  end
end
