defmodule Exdock.Domain.ImageTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Protocol.Snapshot, as: Client
  alias Exdock.Server.State.Storage.Persistence.Image, as: ImagePersistence
  alias Exdock.Server.State.Storage.Persistence.ImageMetadata
  alias Exdock.Server.State.Storage.Persistence.ImageSettings
  alias Exdock.Server.State.Storage.Persistence.Error, as: PersistenceError
  alias Exdock.Domain.Image
  alias Exdock.TestFixtures.DomainImage, as: ImageFixture

  test "load_id/2 returns not_found when the image row is missing" do
    assert ImagePersistence.load_id("node", "sha256:missing") == {:ok, :not_found}
  end

  test "from_client/4 keeps previous metadata and settings while refreshing docker facts" do
    previous_image =
      image(
        metadata: %Image.Metadata{repository_url: "https://custom.example/org/service"},
        settings: %Image.Settings{delete_lock: true}
      )

    updated_image =
      Image.from_client(
        %Client.Image{
          id: "sha256:new-image-id",
          name: "registry.example/new",
          tags: ["registry.example/new:latest"],
          digest: "sha256:new-digest",
          size: 2048,
          shared_size: 256,
          build_date: ~U[2026-06-30 15:43:22Z]
        },
        "node",
        previous_image,
        true
      )

    assert updated_image.id == "sha256:new-image-id"
    assert updated_image.metadata.repository_url == "https://custom.example/org/service"
    assert updated_image.settings.delete_lock == true
  end

  test "load_digest/2 rehydrates a database image into the runtime structure" do
    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(database_image())

    assert {:ok, %Database.ImageMetadata{}} =
             ImageMetadata.insert(%Image.Metadata{repository_url: "https://example.com/app"}, "registry.example/app")

    assert {:ok, %Database.ImageSettings{}} =
             ImageSettings.insert(%Image.Settings{delete_lock: true}, "node", "sha256:image-id")

    assert {:ok, %Image{} = loaded} = ImagePersistence.load_digest("node", "sha256:digest")
    assert loaded.node == "node"
    assert loaded.id == "sha256:image-id"
    assert loaded.tags == ["registry.example/app:latest"]
    assert loaded.size_human == "1.0 KB"
    assert loaded.registry_url == "https://registry.example/app"
    assert loaded.metadata.repository_url == "https://example.com/app"
    assert loaded.settings.delete_lock == true
    assert loaded.in_use == false
  end

  test "read helpers accept string node keys at the database boundary" do
    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(database_image())

    assert {:ok, [%Image{node: "node", id: "sha256:image-id"}]} =
             ImagePersistence.load_node("node")

    assert {:ok, %Image{node: "node", id: "sha256:image-id"}} =
             ImagePersistence.load_id("node", "sha256:image-id")

    assert {:ok, %Image{node: "node", digest: "sha256:digest"}} =
             ImagePersistence.load_digest("node", "sha256:digest")

    assert ImagePersistence.digest_in_db?("node", "sha256:digest")
  end

  test "load_node/1 matches batched metadata by normalized image name" do
    tagged_image = %{database_image() | name: "registry.example/app:latest"}

    assert {:ok, %Database.Image.Record{}} = Database.Image.insert(tagged_image)

    assert {:ok, %Database.ImageMetadata{}} =
             ImageMetadata.insert(
               %Image.Metadata{
                 repository_url: "https://example.com/custom-app"
               },
               tagged_image.name
             )

    assert {:ok,
            [
              %Image{
                metadata: %Image.Metadata{
                  repository_url: "https://example.com/custom-app"
                }
              }
            ]} = ImagePersistence.load_node("node")
  end

  test "insert/1 persists image metadata before the image row" do
    image = image()

    assert :ok = ImagePersistence.insert(image)
    assert %Database.Image.Record{} = Database.Image.by_node_and_id("node", "sha256:image-id")

    assert %Database.ImageMetadata{repository_url: "registry.example/app"} =
             Database.ImageMetadata.by_name("registry.example/app")
  end

  test "insert/1 reports the failing persistence step" do
    image = %{image() | build_date: nil}

    assert {:error, %PersistenceError{operation: :image_insert, cause: changeset}} =
             ImagePersistence.insert(image)

    assert %{build_date: [_ | _]} = errors_on(changeset)
  end

  defp image(opts \\ []) do
    ImageFixture.build(Keyword.merge([settings: %Image.Settings{}], opts))
  end

  defp database_image do
    %Database.Image.Record{
      node: "node",
      id: "sha256:image-id",
      name: "registry.example/app",
      tags: ["registry.example/app:latest"],
      digest: "sha256:digest",
      size: 1024,
      shared_size: 128,
      build_date: ~U[2026-06-30 15:43:22Z]
    }
  end
end
