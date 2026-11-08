defmodule Exdock.TestFixtures.DomainImage do
  @moduledoc false

  alias Exdock.Domain.Image

  @default_build_date ~U[2026-06-30 15:43:22Z]

  @spec build(keyword() | map()) :: Image.t()
  def build(attributes \\ []) do
    attributes = Map.new(attributes)
    {repository_url, attributes} = Map.pop(attributes, :repository_url, "registry.example/app")
    {locked?, attributes} = Map.pop(attributes, :locked, false)

    defaults = %{
      node: "node",
      id: "sha256:image-id",
      name: "registry.example/app",
      tags: ["registry.example/app:latest"],
      digest: "sha256:digest",
      size: 1_024,
      shared_size: 128,
      size_human: "1 KB",
      build_date: @default_build_date,
      metadata: %Image.Metadata{repository_url: repository_url},
      registry_url: "registry.example/app",
      in_use: false,
      settings: %Image.Settings{delete_lock: locked?}
    }

    struct!(Image, Map.merge(defaults, attributes))
  end
end
