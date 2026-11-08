defmodule Exdock.Domain.Image.MetadataTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.ImageMetadata
  alias Exdock.Domain.Image.Metadata

  test "insert/3 stores metadata by normalized image name" do
    metadata = %Metadata{repository_url: "https://example.com/team/app"}

    assert {:ok, %Database.ImageMetadata{name: "registry.example.com/team/app"}} =
             ImageMetadata.insert(metadata, "registry.example.com/team/app:1.2.3")

    assert %Metadata{repository_url: "https://example.com/team/app"} =
             ImageMetadata.load("registry.example.com/team/app:latest")
  end

  test "import/2 applies valid fields and falls back to defaults for invalid values" do
    assert {:ok, %Database.ImageMetadata{repository_url: "https://github.com/alpine"}} =
             ImageMetadata.import(%{"repository_url" => ""}, "alpine:latest")

    assert {:ok, %Database.ImageMetadata{repository_url: "https://example.com/custom"}} =
             ImageMetadata.import(%{"repository_url" => "https://example.com/custom"}, "custom/app:v1")
  end
end
