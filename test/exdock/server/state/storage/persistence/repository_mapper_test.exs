defmodule Exdock.Server.State.Storage.Persistence.Repository.MapperTest do
  use ExUnit.Case, async: true

  alias Exdock.Domain.Repository.{Metadata, Release}
  alias Exdock.Server.State.Storage.Persistence.Repository.Mapper

  test "maps metadata through an explicit database record" do
    metadata = %Metadata{state: :rate_limit, last_check: ~U[2026-08-01 12:00:00Z]}

    assert %Exdock.Database.Repository{
             url: "https://github.com/acme/example",
             releases_page: :rate_limit,
             last_check: ~U[2026-08-01 12:00:00Z]
           } = Mapper.metadata_record(metadata, "https://github.com/acme/example")
  end

  test "maps only release fields understood by persistence" do
    release =
      Release.new(
        :github,
        "https://github.com/acme/example",
        "acme/example",
        "v1.0.0",
        "https://github.com/acme/example/releases/v1.0.0",
        "Notes",
        ~U[2026-08-01 12:00:00Z]
      )

    attributes = Mapper.release_attributes(release)

    assert Map.keys(attributes) |> Enum.sort() ==
             Enum.sort([
               :compressed_description,
               :name,
               :release_url,
               :repository,
               :source,
               :time_released,
               :version
             ])

    refute Map.has_key?(attributes, :compressed_html_description)
    assert Mapper.same_release?(release, release)
  end
end
