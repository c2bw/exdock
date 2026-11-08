defmodule ExdockWeb.ReleasesLiveTest do
  use ExdockWeb.LiveCase

  import Phoenix.LiveViewTest

  alias Exdock.ReadModel.{Release, Repository}
  alias Exdock.Domain.Repository, as: DomainRepository
  alias Exdock.Server.State.Storage.Repositories

  describe "releases live view" do
    test "renders the releases page shell with actionable controls", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/releases")

      assert has_element?(view, "#app-shell")
      assert has_element?(view, "#releases-index")
      assert has_element?(view, "#releases-live-page")
      assert has_element?(view, "aside")
      assert has_element?(view, "#releases-fetch-button")
      refute has_element?(view, "#releases-repositories-button")
      assert has_element?(view, "#releases-sources-button[aria-controls='repositories_manager']", "Sources")
      assert has_element?(view, "#repositories_manager #repositories_manager-component")
      assert has_element?(view, "#repositories_manager-component > header")
      assert has_element?(view, "#repositories_manager-title", "Sources & releases")
      refute has_element?(view, "[aria-label='Sources summary']")
      assert has_element?(view, "#repositories-manager-empty")
      assert has_element?(view, "#about-page")
      assert has_element?(view, "#settings-page")
    end

    test "sources modal exposes repository links and refresh controls", %{conn: conn} do
      %{repository: repository} = seed_repository_release()

      {:ok, view, _html} = live(conn, ~p"/releases")

      assert has_element?(
               view,
               "#repositories-manager-list a[href='#{repository}'][target='_blank'][rel='noopener noreferrer']"
             )

      assert has_element?(view, "#repositories-manager-list a[href='#{repository}']", repository)

      assert has_element?(
               view,
               "#repositories-manager-list [data-role='repository-source'] button[phx-click='repository_releases_fetch'][phx-value-repository='#{repository}']"
             )

      assert has_element?(view, "#repositories-manager-list [data-role='repository-source']", "1 release")
    end

    test "rebuilds cached release summaries when repository broadcasts arrive", %{conn: conn} do
      %{repository: repository} = seed_repository_release()
      {:ok, view, _html} = live(conn, ~p"/releases")

      assert has_element?(view, "#repositories-manager-list a[href='#{repository}']")

      send(view.pid, {:repositories, []})

      assert has_element?(view, "#repositories-manager-empty")
      refute has_element?(view, "#repositories-manager-list a[href='#{repository}']")
    end

    test "renders selected repository release list", %{conn: conn} do
      %{repository: repository, version: version} = seed_repository_release()
      encoded = ExdockWeb.PageLive.Utils.URLParam.encode(repository)

      {:ok, view, _html} = live(conn, ~p"/releases/#{encoded}")

      assert has_element?(view, "#releases-live-page")
      assert has_element?(view, "a[href='/releases']")
      assert has_element?(view, "#release-history-header")
      assert has_element?(view, "#release-history-items [data-role='release-history-item']")
      assert has_element?(view, "#sidebar-repositories-summary")
      assert has_element?(view, "#sidebar-repositories-summary", "Releases available")
      assert has_element?(view, "p", version)
      assert has_element?(view, "time[data-role='repository-last-fetched']")
      assert has_element?(view, "time[data-role='repository-last-fetched-relative']", "fetched")
      assert has_element?(view, "article[data-role='release-markdown'].release-markdown")
    end

    test "fetch button accepts the value metadata sent by browser clicks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/releases")

      view
      |> element("#releases-fetch-button")
      |> render_click(%{"value" => ""})

      assert has_element?(view, "#releases-live-page")
      refute has_element?(view, "#flash-error", "Invalid releases fetch request")
    end

    test "malformed repository fetch does not terminate the page or fall back to fetch-all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/releases")

      render_click(view, "repository_releases_fetch", %{"repository" => ""})

      assert has_element?(view, "#releases-live-page")
      assert has_element?(view, "#flash-error", "Invalid releases fetch request")
    end

    test "redirects invalid repository route params back to releases", %{conn: conn} do
      invalid_repository = Base.url_encode64(<<255>>, padding: false)

      assert {:error, {:live_redirect, %{to: "/releases"}}} = live(conn, "/releases/#{invalid_repository}")
    end

    test "selected repository release list is newest-first and exposes repository fetch", %{conn: conn} do
      %{repository: repository, newest_version: newest_version, oldest_version: oldest_version} = seed_repository_releases()
      encoded = ExdockWeb.PageLive.Utils.URLParam.encode(repository)

      {:ok, view, html} = live(conn, ~p"/releases/#{encoded}")

      assert has_element?(view, "#releases-live-page")
      assert html_position(html, newest_version) < html_position(html, oldest_version)
      assert has_element?(view, "details[id='#{release_description_id(repository, newest_version)}']")
      assert has_element?(view, "details[id='#{release_description_id(repository, oldest_version)}']")

      render_click(view, "repository_releases_fetch", %{"repository" => repository})

      assert has_element?(view, "#releases-live-page")
    end
  end

  defp seed_repository_release do
    repository = "https://github.com/alpine"
    version = "v#{System.unique_integer([:positive])}.0.0"
    image_name = "alpine:v#{System.unique_integer([:positive])}"
    node_id = "releases_node_#{System.unique_integer([:positive])}"
    image_id = "release-test-#{System.unique_integer([:positive])}"

    release =
      DomainRepository.Release.new(
        :github,
        repository,
        "exdock/releases",
        version,
        "#{repository}/releases/#{version}",
        "Release notes for #{version}",
        ~U[2026-06-01 12:00:00Z]
      )

    {:ok, _} =
      %Exdock.Database.Image.Record{
        node: node_id,
        id: image_id,
        name: image_name,
        tags: ["alpine"],
        digest: "sha256:#{String.duplicate("b", 16)}",
        size: 22_000_000,
        shared_size: 2_048,
        build_date: ~U[2026-01-01 00:00:00Z]
      }
      |> Exdock.Database.Image.insert()

    :ok =
      Exdock.Runtime.Coordinator.node_is_up(node_id, %{"platform" => "linux/amd64"})

    assert_repository_reference!(repository)

    :ok =
      Exdock.Runtime.Coordinator.commit_state_change(Repositories.Change.releases([{:ok, repository, [release]}]))

    assert_release_in_state!(repository, version)

    %{repository: repository, version: version}
  end

  defp seed_repository_releases do
    repository = "https://github.com/exdock/releases-#{System.unique_integer([:positive])}"
    newest_version = "v9.#{System.unique_integer([:positive])}.0"
    oldest_version = "v1.#{System.unique_integer([:positive])}.0"

    releases = [
      repository_release(repository, oldest_version, ~U[2026-01-01 12:00:00Z]),
      repository_release(repository, newest_version, ~U[2026-06-01 12:00:00Z])
    ]

    seed_repository_reference(repository)

    :ok =
      Exdock.Runtime.Coordinator.commit_state_change(Repositories.Change.releases([{:ok, repository, releases}]))

    assert_release_in_state!(repository, newest_version)
    assert_release_in_state!(repository, oldest_version)

    %{repository: repository, newest_version: newest_version, oldest_version: oldest_version}
  end

  defp repository_release(repository, version, released_at) do
    DomainRepository.Release.new(
      :github,
      repository,
      "exdock/releases",
      version,
      "#{repository}/releases/#{version}",
      "Release notes for #{version}",
      released_at
    )
  end

  defp seed_repository_reference(repository) do
    node_id = "releases_node_#{System.unique_integer([:positive])}"
    image_id = "release-test-#{System.unique_integer([:positive])}"
    image_name = "image-#{image_id}:latest"

    {:ok, _} =
      %Exdock.Database.Image.Record{
        node: node_id,
        id: image_id,
        name: image_name,
        tags: [image_name],
        digest: "sha256:#{String.duplicate("c", 16)}",
        size: 22_000_000,
        shared_size: 2_048,
        build_date: ~U[2026-01-01 00:00:00Z]
      }
      |> Exdock.Database.Image.insert()

    subscribe_to_operations!()
    assert {:ok, _operation_id} = Exdock.Operations.set_image_repository_url(image_name, repository)
    assert %{status: :completed} = await_operation!(:set_image_repository_url)

    :ok =
      Exdock.Runtime.Coordinator.node_is_up(node_id, %{"platform" => "linux/amd64"})

    assert_repository_reference!(repository)
  end

  defp html_position(html, text) do
    case :binary.match(html, text) do
      {position, _length} -> position
      :nomatch -> flunk("Expected #{inspect(text)} to be rendered")
    end
  end

  defp release_description_id(repository, version) do
    ExdockWeb.PageLive.Utils.IdUtils.create_id("#{repository}_#{version}_details")
  end

  defp assert_repository_reference!(repository) do
    assert Enum.any?(Exdock.ReadModel.page([:repositories]).repositories, fn %Repository{url: url} ->
             url == repository
           end),
           "Expected repository #{repository} to be referenced by a node image"
  end

  defp assert_release_in_state!(repository, version) do
    assert Enum.any?(Exdock.ReadModel.page([:repositories]).repositories, fn
             %Repository{url: ^repository, releases: releases} ->
               Enum.any?(releases, fn
                 %Release{version: ^version} -> true
                 _ -> false
               end)

             _ ->
               false
           end),
           "Expected repository #{repository} to expose release #{version}"
  end
end
