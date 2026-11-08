defmodule Exdock.Database.Image.MapperTest do
  use ExUnit.Case, async: true

  alias Exdock.Database.Image.{Changeset, Mapper, Record, Row}

  test "maps runtime records to stored rows and back" do
    record = record(tags: ["example/app:latest", "example/app:stable"])

    stored = Mapper.to_row(record)

    assert stored.node == "node"
    assert stored.tags == "example/app:latest,example/app:stable"

    row = struct!(Row, Map.put(stored, :image_key, Mapper.key(record.node, record.id)))

    assert Mapper.to_record(row) == record
  end

  test "round-trips empty and missing persisted tags" do
    assert Mapper.serialize_tags([]) == ""
    assert Mapper.deserialize_tags("") == []
    assert Mapper.deserialize_tags(nil) == []
  end

  test "changeset derives the composite key and normalizes datetime precision" do
    build_date = ~U[2026-07-30 12:34:56.987654Z]

    changeset =
      record(build_date: build_date)
      |> Mapper.to_row()
      |> Changeset.build()

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :image_key) == "node:sha256:image"
    assert Ecto.Changeset.get_field(changeset, :build_date) == ~U[2026-07-30 12:34:56Z]
  end

  test "changeset rejects incomplete stored rows" do
    refute Changeset.build(%{node: "node", tags: ""}).valid?
  end

  defp record(opts) do
    %Record{
      node: Keyword.get(opts, :node, "node"),
      id: Keyword.get(opts, :id, "sha256:image"),
      name: Keyword.get(opts, :name, "example/app"),
      tags: Keyword.get(opts, :tags, []),
      digest: Keyword.get(opts, :digest, "sha256:digest"),
      size: Keyword.get(opts, :size, 1024),
      shared_size: Keyword.get(opts, :shared_size, 128),
      build_date: Keyword.get(opts, :build_date, ~U[2026-07-30 12:34:56Z])
    }
  end
end
