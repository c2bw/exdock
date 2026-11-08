defmodule Exdock.ReadModel.RepositoryOverviewTest do
  use ExUnit.Case, async: true

  alias Exdock.ReadModel.{Release, Repository, RepositoryOverview, RepositoryPage}

  test "derives sorted previews, page counts, and release totals" do
    older = release("older", ~U[2026-01-01 00:00:00Z])
    newer = release("newer", ~U[2026-06-01 00:00:00Z])

    repositories = [
      %Repository{
        url: "https://example.com/older",
        page: %RepositoryPage{state: :ok, last_check: ~U[2026-07-01 00:00:00Z]},
        releases: [older, release("older-2", ~U[2025-01-01 00:00:00Z])]
      },
      %Repository{
        url: "https://example.com/newer",
        page: %RepositoryPage{state: :rate_limit, last_check: ~U[2026-07-01 00:00:00Z]},
        releases: [newer]
      },
      %Repository{
        url: "https://example.com/pending",
        page: %RepositoryPage{state: :error, last_check: nil},
        releases: []
      }
    ]

    overview = RepositoryOverview.from_repositories(repositories)

    assert [{_newer_page, ^newer, 1}, {_older_page, ^older, 2}] = overview.previews
    assert overview.total_release_count == 3
    assert overview.page_counts.ok == 1
    assert overview.page_counts.rate_limit == 1
    assert overview.page_counts.unknown == 1
    assert overview.page_counts.error == 0
  end

  defp release(version, time_released) do
    %Release{
      version: version,
      time_released: time_released
    }
  end
end
