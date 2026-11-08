defmodule ExdockWeb.ReleasesLive.Manager.RepositorySourceRowTest do
  use ExUnit.Case, async: true

  alias Exdock.ReadModel.{Repository, RepositoryPage}
  alias ExdockWeb.ReleasesLive.Manager.RepositorySourceRow

  test "normalizes unchecked sources and orders rows by URL" do
    later = %Repository{
      url: "https://example.com/zeta",
      page: %RepositoryPage{state: :ok, last_check: nil},
      releases: [:one]
    }

    earlier = Repository.default("https://example.com/alpha")

    assert [first, second] = RepositorySourceRow.build_all([later, earlier], DateTime.utc_now())

    assert %RepositorySourceRow{
             url: "https://example.com/alpha",
             state: :unknown,
             state_label: "Pending",
             release_count_label: "0 releases",
             last_check_label: "Not checked yet"
           } = first

    assert %RepositorySourceRow{
             url: "https://example.com/zeta",
             state: :unknown,
             release_count: 1,
             release_count_label: "1 release"
           } = second
  end
end
