defmodule Exdock.ImageReferenceTest do
  use ExUnit.Case, async: true

  alias Exdock.ImageReference

  test "infers docker hub official image urls" do
    assert ImageReference.registry_url("alpine:latest") == "https://hub.docker.com/_/alpine"
    assert ImageReference.repository_url("alpine:latest") == "https://github.com/alpine"
    assert ImageReference.categorize_registry("alpine:latest") == "Docker Hub"
  end

  test "infers docker hub namespace image urls" do
    assert ImageReference.registry_url("library/postgres:16") == "https://hub.docker.com/r/library/postgres"
    assert ImageReference.repository_url("library/postgres:16") == "https://github.com/library/postgres"
  end

  test "infers known registry urls" do
    assert ImageReference.registry_url("docker.io/library/alpine:latest") == "https://hub.docker.com/r/library/alpine"
    assert ImageReference.registry_url("quay.io/org/app:v1") == "https://quay.io/repository/org/app"
    assert ImageReference.registry_url("ghcr.io/org/app:v1") == "https://ghcr.io/org/app"
    assert ImageReference.registry_url("gcr.io/project/app:v1") == "https://gcr.io/project/app"

    assert ImageReference.categorize_registry("quay.io/org/app:v1") == "Quay"
    assert ImageReference.categorize_registry("docker.io/library/alpine:latest") == "Docker Hub"
    assert ImageReference.categorize_registry("ghcr.io/org/app:v1") == "GitHub"
    assert ImageReference.categorize_registry("gcr.io/project/app:v1") == "Google"
  end

  test "infers private registry urls from the registry host" do
    assert ImageReference.registry_url("registry.example.com/team/app:v1") == "https://registry.example.com/team/app"
    assert ImageReference.repository_url("registry.example.com/team/app:v1") == "https://github.com/team/app"
    assert ImageReference.categorize_registry("registry.example.com/team/app:v1") == "registry.example.com"
  end

  test "normalizes and truncates tags" do
    assert ImageReference.normalize_tag("alpine") == "alpine:latest"
    assert ImageReference.normalize_tag("alpine:3.20") == "alpine:3.20"

    assert ImageReference.normalize_tag("registry.example:5000/team/app") ==
             "registry.example:5000/team/app:latest"

    digest = "alpine@sha256:#{String.duplicate("a", 64)}"
    assert ImageReference.normalize_tag(digest) == digest
    assert ImageReference.truncate_tag("docker.io/library/alpine:latest") == "alpine"

    assert ImageReference.truncate_tag("registry.example:5000/team/app:1.2") ==
             "registry.example:5000/team/app"
  end
end
