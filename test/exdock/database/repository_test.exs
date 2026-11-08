defmodule Exdock.Database.RepositoryTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Repo
  @url "https://github.com/openai/example"

  test "insert/1 stores atom state as a string and by_url/1 restores atoms" do
    metadata =
      Database.Repository.new(%{
        url: @url,
        state: :rate_limit,
        last_check: ~U[2026-06-30 15:43:22Z]
      })

    assert {:ok, %Database.Repository{releases_page: :rate_limit}} = Database.Repository.insert(metadata)

    assert %Database.Repository{
             url: @url,
             releases_page: :rate_limit,
             last_check: ~U[2026-06-30 15:43:22Z]
           } = Database.Repository.by_url(@url)
  end

  test "load_all/0 and urls/0 expose every stored repository" do
    insert_repository(@url, :ok)
    insert_repository("https://github.com/openai/other", :unsupported)

    assert Database.Repository.urls() |> Enum.sort() == [@url, "https://github.com/openai/other"]
    assert Database.Repository.load_all() |> Enum.map(& &1.releases_page) |> Enum.sort() == [:ok, :unsupported]
  end

  test "unknown stored release page states fall back to error" do
    assert {:ok, %Database.Repository{}} =
             Repo.insert(%Database.Repository{
               url: @url,
               releases_page: "not-a-known-state",
               last_check: ~U[2026-06-30 15:43:22Z]
             })

    assert %Database.Repository{releases_page: :error} = Database.Repository.by_url(@url)
  end

  defp insert_repository(url, state) do
    metadata =
      Database.Repository.new(%{
        url: url,
        state: state,
        last_check: ~U[2026-06-30 15:43:22Z]
      })

    Database.Repository.insert(metadata)
  end
end
