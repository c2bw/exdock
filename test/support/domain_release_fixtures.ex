defmodule Exdock.TestFixtures.DomainRelease do
  @moduledoc false

  alias Exdock.Domain.Repository.Release

  @default_repository "https://github.com/openai/example"
  @default_time ~U[2026-06-30 15:43:22Z]

  @spec build(keyword() | map()) :: Release.t()
  def build(attributes \\ []) do
    attributes = Map.new(attributes)
    repository = Map.get(attributes, :repository, @default_repository)
    version = Map.get(attributes, :version, "v1.0.0")

    Release.new(
      Map.get(attributes, :source, :github),
      repository,
      Map.get(attributes, :name, "openai/example"),
      version,
      Map.get(attributes, :release_url, "#{repository}/releases/#{version}"),
      Map.get(attributes, :description, "Notes"),
      Map.get(attributes, :time_released, @default_time)
    )
  end
end
