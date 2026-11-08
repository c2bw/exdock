defmodule Exdock.Domain.Repository.ReleaseTest do
  use ExUnit.Case, async: true

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.Repository, as: RepositoryPersistence
  alias Exdock.Domain.Repository.Release

  @repository "https://github.com/openai/example"

  test "new accepts ISO8601 release times and stores compressed markdown/html descriptions" do
    release = release("v1.0.0", "2026-06-01T12:34:56Z", "## Notes")

    assert release.time_released == ~U[2026-06-01 12:34:56Z]
    assert :zlib.gunzip(release.compressed_description) == "## Notes"
    assert :zlib.gunzip(release.compressed_html_description) =~ "<h2>"
  end

  test "new normalizes ISO8601 release times with offsets" do
    release = release("v1.0.0", "2026-06-01T14:34:56+02:00", "Notes")

    assert release.time_released == ~U[2026-06-01 12:34:56Z]
  end

  test "new normalizes nil descriptions to empty compressed strings" do
    release = release("v1.0.0", ~U[2026-06-01 12:34:56Z], nil)

    assert :zlib.gunzip(release.compressed_description) == ""
    assert :zlib.gunzip(release.compressed_html_description) == ""
  end

  test "new removes embedded HTML from rendered release descriptions" do
    description = "## Notes\n\n<strong>provider HTML</strong>\n\n<img src=x onerror=alert(1)>\n\n<script>alert(1)</script>"
    release = release("v1.0.0", ~U[2026-06-01 12:34:56Z], description)
    html = :zlib.gunzip(release.compressed_html_description)

    assert html =~ "<h2>"
    refute html =~ "<strong"
    refute html =~ "<img"
    refute html =~ "onerror"
    refute html =~ "<script"
  end

  test "new tolerates malformed HTML in provider release descriptions" do
    description = "## Notes\n\nSafe content.\n\n<details>\nUnclosed provider content"
    release = release("v1.0.0", ~U[2026-06-01 12:34:56Z], description)
    html = :zlib.gunzip(release.compressed_html_description)

    assert :zlib.gunzip(release.compressed_description) == description
    assert html =~ "<h2>"
    assert html =~ "Safe content."
    refute html =~ "<details>"
  end

  test "new removes dangerous release-description URLs and preserves safe Markdown links" do
    description = "[unsafe](javascript&#58;alert(1)) [safe](https://example.com/releases?a=1&b=2)"
    release = release("v1.0.0", ~U[2026-06-01 12:34:56Z], description)
    html = :zlib.gunzip(release.compressed_html_description)

    refute html =~ "javascript"
    assert html =~ ~s(href="https://example.com/releases?a=1&amp;b=2")
    assert html =~ ">safe</a>"
  end

  test "new permits mail links without permitting mail URLs for images" do
    description = "[email](mailto:team@example.com) ![unsafe](mailto:team@example.com) ![safe](https://example.com/logo.png)"
    release = release("v1.0.0", ~U[2026-06-01 12:34:56Z], description)
    html = :zlib.gunzip(release.compressed_html_description)

    assert html =~ ~s(href="mailto:team@example.com")
    refute html =~ ~s(src="mailto:team@example.com")
    assert html =~ ~s(src="https://example.com/logo.png")
  end

  test "new renders GFM tables with safe column alignment" do
    description = "| Name | Status |\n| :--- | ---: |\n| API | Ready |"
    release = release("v1.0.0", ~U[2026-06-01 12:34:56Z], description)
    html = :zlib.gunzip(release.compressed_html_description)

    assert html =~ "<table>"
    assert html =~ "<thead>"
    assert html =~ "<tbody>"
    assert html =~ ~s(align="left")
    assert html =~ ~s(align="right")
  end

  test "new renders GitHub alerts without exposing their marker text" do
    description = "> [!TIP]\n> Cache the image.\n\n> [!WARNING]\n> Back up the database first."
    release = release("v1.0.0", ~U[2026-06-01 12:34:56Z], description)
    html = :zlib.gunzip(release.compressed_html_description)

    assert html =~ ~s(class="markdown-alert markdown-alert-tip")
    assert html =~ ~s(class="markdown-alert markdown-alert-warning")
    assert html =~ ~r/class="markdown-alert-title">\s*Tip\s*<\/p>/
    assert html =~ "Cache the image."
    refute html =~ "[!TIP]"
    refute html =~ "[!WARNING]"
  end

  test "new uses an explicit fallback for invalid release time strings" do
    fallback = ~U[2026-07-31 12:00:00Z]
    release = release("v1.0.0", "not-a-date", "Notes", fallback)

    assert release.time_released == fallback
  end

  test "new from database release inflates the stored description" do
    original = release("v1.0.0", ~U[2026-06-01 12:34:56Z], "Notes")

    database_release = %Database.RepositoryRelease{
      url: original.repository,
      version: original.version,
      release_url: original.release_url,
      source: original.source,
      name: original.name,
      description: original.compressed_description,
      time_released: original.time_released
    }

    rebuilt = Release.from_persisted(database_release)

    assert rebuilt.repository == original.repository
    assert rebuilt.version == original.version
    assert :zlib.gunzip(rebuilt.compressed_description) == "Notes"
  end

  test "new from database release rebuilds rendered html from stored markdown" do
    database_release = %Database.RepositoryRelease{
      url: @repository,
      version: "v1.0.0",
      release_url: "#{@repository}/releases/v1.0.0",
      source: :github,
      name: "openai/example",
      description: :zlib.gzip("## Notes"),
      time_released: ~U[2026-06-01 12:34:56Z]
    }

    rebuilt = Release.from_persisted(database_release)

    assert :zlib.gunzip(rebuilt.compressed_description) == "## Notes"
    assert :zlib.gunzip(rebuilt.compressed_html_description) =~ "<h2>"
  end

  test "same_version compares repository and version only" do
    release = release("v1.0.0", ~U[2026-06-01 12:34:56Z], "Notes")
    same = release("v1.0.0", ~U[2026-07-01 12:34:56Z], "Updated")
    different = release("v2.0.0", ~U[2026-07-01 12:34:56Z], "Updated")

    assert Release.same_version(release, same)
    refute Release.same_version(release, different)
  end

  test "insert_if_different skips identical database releases" do
    release = release("v1.0.0", ~U[2026-06-01 12:34:56Z], "Notes")

    assert RepositoryPersistence.insert_if_different(release, release) == {:ok, :same}
  end

  defp release(version, time_released, description, fallback \\ ~U[2026-07-31 00:00:00Z]) do
    if is_binary(time_released) do
      Release.new(
        :github,
        @repository,
        "openai/example",
        version,
        "#{@repository}/releases/#{version}",
        description,
        time_released,
        fallback
      )
    else
      Release.new(
        :github,
        @repository,
        "openai/example",
        version,
        "#{@repository}/releases/#{version}",
        description,
        time_released
      )
    end
  end
end
