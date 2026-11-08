defmodule Exdock.Server.State.Storage.Cluster.PersistenceTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Cluster.Persistence
  alias Exdock.Server.State.Storage.Cluster.Persistence.Plan
  alias Exdock.Server.State.Storage.Persistence.ImageMetadata
  alias Exdock.Domain.{Image, Node}

  test "rolls back earlier writes when a later snapshot record fails" do
    node = "transaction-rollback-node"

    node_record = %{
      Node.default(node)
      | fetched_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    invalid_image = %Image{
      node: node,
      id: nil,
      name: "invalid-image",
      tags: [],
      digest: nil,
      size: nil,
      shared_size: nil,
      build_date: nil,
      metadata: Image.Metadata.default("invalid-image"),
      settings: Image.Settings.default(),
      in_use: false
    }

    plan = %Plan{
      node: node,
      node_record: node_record,
      images: [invalid_image]
    }

    assert {:error, _reason} = Persistence.persist(plan)
    assert Database.Nodes.load(node) == nil
    assert ImageMetadata.load("invalid-image") == nil
  end
end
