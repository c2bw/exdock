defmodule Exdock.Server.Jobs.Local.Releases.ResponseMapperTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs.Local.Releases.ResponseMapper
  alias Exdock.Domain.Repository

  test "maps mixed-key GitLab payloads through the provider profile" do
    payload = [
      %{
        "tag_name" => "v2.0.0",
        "description" => "release notes",
        :links => %{"self" => "https://gitlab.com/group/example/-/releases/v2.0.0"},
        :released_at => "2026-07-30T12:00:00Z"
      }
    ]

    assert [
             %Repository.Release{
               source: :gitlab,
               repository: "https://gitlab.com/group/example",
               name: "group/example",
               version: "v2.0.0",
               release_url: "https://gitlab.com/group/example/-/releases/v2.0.0"
             }
           ] =
             ResponseMapper.parse(
               :gitlab,
               "group/example",
               "https://gitlab.com/group/example",
               payload,
               ~U[2026-07-31 00:00:00Z]
             )
  end

  test "uses the explicit fetch time when a provider timestamp is malformed" do
    fetched_at = ~U[2026-07-31 12:00:00Z]

    [release] =
      ResponseMapper.parse(
        :gitlab,
        "group/example",
        "https://gitlab.com/group/example",
        [%{"tag_name" => "v2", "released_at" => "invalid"}],
        fetched_at
      )

    assert release.time_released == fetched_at
  end
end
