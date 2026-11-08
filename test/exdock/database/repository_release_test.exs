defmodule Exdock.Database.RepositoryReleaseTest do
  use Exdock.DataCase, async: false

  alias Exdock.Database
  alias Exdock.Repo
  alias Exdock.Domain.Repository.Release

  @url "https://github.com/openai/example"

  test "insert/1 stores source as a string and load/1 restores provider atoms" do
    release =
      :gitlab
      |> release("v1.0.0", ~U[2026-06-30 15:43:22.987654Z])
      |> Map.from_struct()
      |> Database.RepositoryRelease.new()

    assert {:ok, %Database.RepositoryRelease{source: :gitlab}} = Database.RepositoryRelease.insert(release)

    assert [
             %Database.RepositoryRelease{
               url: @url,
               version: "v1.0.0",
               source: :gitlab,
               time_released: ~U[2026-06-30 15:43:22Z]
             }
           ] = Database.RepositoryRelease.load(@url)
  end

  test "load/0 returns every stored release in application format" do
    insert_release(@url, "v1.0.0", :github)
    insert_release("https://gitlab.com/openai/example", "v2.0.0", :gitlab)

    assert Database.RepositoryRelease.load()
           |> Enum.map(&{&1.url, &1.version, &1.source})
           |> Enum.sort() == [
             {@url, "v1.0.0", :github},
             {"https://gitlab.com/openai/example", "v2.0.0", :gitlab}
           ]
  end

  test "unknown stored sources fall back to github" do
    assert {:ok, %Database.RepositoryRelease{}} =
             Repo.insert(%Database.RepositoryRelease{
               url: @url,
               version: "v1.0.0",
               release_url: "#{@url}/releases/v1.0.0",
               source: "not-a-known-source",
               name: "openai/example",
               description: :zlib.gzip("Notes"),
               time_released: ~U[2026-06-30 15:43:22Z]
             })

    assert [%Database.RepositoryRelease{source: :github}] = Database.RepositoryRelease.load(@url)
  end

  defp insert_release(url, version, source) do
    source
    |> release(url, version, ~U[2026-06-30 15:43:22Z])
    |> Map.from_struct()
    |> Database.RepositoryRelease.new()
    |> Database.RepositoryRelease.insert()
  end

  defp release(source, version, time_released), do: release(source, @url, version, time_released)

  defp release(source, url, version, time_released) do
    Release.new(source, url, "openai/example", version, "#{url}/releases/#{version}", "Notes", time_released)
  end
end
