defmodule ExdockWeb.HomepageLiveTest do
  use ExdockWeb.LiveCase

  import Phoenix.LiveViewTest

  alias Exdock.ReadModel.ClusterNode
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Domain
  alias ExdockWeb.HomepageLiveTest.{AsideUserInputHarness, MassManagerHarness, RepositoryOverridesHarness}
  alias ExdockWeb.PageLive.Utils.IdUtils

  describe "homepage live view" do
    test "renders homepage shell and shared UI surface", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#app-shell")
      assert has_element?(view, "#app-navbar")
      assert has_element?(view, "#theme-toggle[phx-hook='DarkThemeToggle']")
      assert has_element?(view, "#theme-system[data-theme-option='system'][aria-pressed='true']")
      assert has_element?(view, "#theme-light[data-theme-option='light']")
      assert has_element?(view, "#theme-dark[data-theme-option='dark']")
      assert has_element?(view, "#homepage-index")
      assert has_element?(view, "#cluster-status-bar[aria-live='polite']")
      assert has_element?(view, "#cluster-status-button[aria-haspopup='dialog']")
      assert has_element?(view, "aside[aria-label='Cluster controls']")
      assert has_element?(view, "#homepage-registry-fetch-button")
      assert has_element?(view, "#homepage-node-refresh-button")
      assert has_element?(view, "#sidebar-resource-summary")
      assert has_element?(view, "#sidebar-footer nav[aria-label='Exdock resources']")
      assert has_element?(view, "#sidebar-about-button", "About")
      assert has_element?(view, "#sidebar-github-link", "GitHub")
      assert has_element?(view, "#about-page")
      assert has_element?(view, "#settings-page")
    end

    test "renders seeded node summary on load", %{conn: conn} do
      %{node: node} = seed_node()

      {:ok, view, _html} = live(conn, ~p"/")

      summary_id = IdUtils.create_id("nodesummary#{node}")
      node_settings_form_id = IdUtils.create_id("node-settings-component" <> summary_id) <> "-form"

      assert has_element?(view, "#homepage-index")
      assert has_element?(view, "##{summary_id}-header")
      assert has_element?(view, "##{summary_id}-header p", node)
      assert has_element?(view, "##{node_settings_form_id}")
    end

    test "submits node settings through the rendered node form", %{conn: conn} do
      %{node: node} = seed_node()
      {:ok, view, _html} = live(conn, ~p"/")

      summary_id = IdUtils.create_id("nodesummary#{node}")
      node_settings_form_id = IdUtils.create_id("node-settings-component" <> summary_id) <> "-form"
      web_ui = "https://#{node}.example"
      subscribe_to_operations!()

      view
      |> form("##{node_settings_form_id}", %{
        "node" => node,
        "key" => "web_ui",
        "val" => web_ui
      })
      |> render_submit()

      assert %{status: :completed} = await_operation!(:change_node_setting)
      configuration = Exdock.ReadModel.page([]).server_configuration
      assert Exdock.Configuration.node_settings(configuration, node).web_ui == web_ui
    end

    test "dispatches node/registry actions without leaving homepage", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#homepage-index")

      view
      |> element("#homepage-node-refresh-button")
      |> render_click()

      assert has_element?(view, "#homepage-index")

      view
      |> element("#homepage-registry-fetch-button")
      |> render_click()

      assert has_element?(view, "#homepage-index")
    end

    test "dispatches node-scoped summary actions without leaving homepage", %{conn: conn} do
      %{node: node} = seed_node()

      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("button[phx-click='registry_fetch_node'][phx-value-nodename='#{node}']")
      |> render_click()

      assert has_element?(view, "#homepage-index")

      view
      |> element("button[phx-click='node_refresh'][phx-value-nodename='#{node}']")
      |> render_click()

      assert has_element?(view, "#homepage-index")
    end

    test "mass manager groups outdated running containers and emits bulk action payloads", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, MassManagerHarness)

      assert has_element?(view, "#mass-manager-harness", "Mass Container Manager")
      assert has_element?(view, "#mass-container-manager-title")
      assert has_element?(view, "#mass-container-manager-description")
      assert has_element?(view, "#masscontainermanagerpriority4")
      assert has_element?(view, "#masscontainermanagerpriority4 tbody.first-row-divider-subtle")
      assert has_element?(view, "#masscontainermanagerpriority4 tbody tr[id]")
      assert has_element?(view, "button[aria-label='Pull']")
      assert has_element?(view, "button[aria-label='Recreate']")
      assert has_element?(view, "button[aria-label='Pull and recreate']")

      view
      |> element("button[aria-label='Pull']")
      |> render_click()

      assert has_element?(view, "#last-mass-manager-event", "image-pull:mass_node,repo/api:latest")

      view
      |> element("button[aria-label='Recreate']")
      |> render_click()

      assert has_element?(view, "#last-mass-manager-event", "container-recreate:mass_node,api:false")

      view
      |> element("button[aria-label='Pull and recreate']")
      |> render_click()

      assert has_element?(view, "#last-mass-manager-event", "container-recreate:mass_node,api:true")
    end

    test "mass manager accepts the homepage full-container snapshot", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, AsideUserInputHarness)

      assert has_element?(view, "#masscontainermanagerpriority4")
      assert has_element?(view, "button[aria-label='Pull']")
    end

    test "renders repository override metadata as its URL", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, RepositoryOverridesHarness)

      assert has_element?(view, "td", "alpine:latest")
      assert has_element?(view, "td", "https://github.com/alpine")
      assert has_element?(view, "#repository-overrides-manager")
      assert has_element?(view, "#repository-overrides tr[id]")
      assert has_element?(view, "#repository-overrides-import-form")
      assert has_element?(view, "#repository-overrides-import-button")
    end

    test "submits repository overrides through the rendered settings form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      image_name = "repo/form-import-#{System.unique_integer([:positive])}:latest"
      repository_url = "https://github.com/example/form-import"
      subscribe_to_operations!()

      view
      |> element("button[aria-label='Settings']")
      |> render_click()

      assert has_element?(view, "#repository-overrides-import-form")

      view
      |> form("#repository-overrides-import-form", %{
        "repositories_input" => "#{image_name} -> #{repository_url}"
      })
      |> render_submit()

      assert %{status: :completed} = await_operation!(:set_image_repository_urls)

      assert %{repository_url: ^repository_url} =
               Exdock.Server.State.Storage.Persistence.ImageMetadata.load(image_name)
    end
  end

  defp seed_node do
    node = "homepage-node-#{System.unique_integer([:positive])}"

    :ok =
      node
      |> Domain.Node.default()
      |> Domain.Node.set_fetched_at(DateTime.utc_now())
      |> NodePersistence.insert()

    :ok =
      Exdock.Runtime.Coordinator.node_is_up(
        node,
        %{"platform" => "linux/amd64"}
      )

    assert %ClusterNode{} =
             Exdock.ReadModel.page([:nodes]).nodes
             |> Map.fetch!(to_string(node))

    %{node: node}
  end
end
