defmodule ExdockWeb.ContainersLive.ListTest do
  use ExdockWeb.LiveCase

  import Phoenix.LiveViewTest

  alias ExdockWeb.ContainersLiveTest.ContainersListHarness

  test "partitions containers by running state and image status", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, ContainersListHarness)

    assert has_element?(view, "#unkORerrcontainers_list_component", "api-unknown")
    assert has_element?(view, "#outdatedcontainers_list_component", "api-outdated")
    assert has_element?(view, "#okcontainers_list_component", "api-updated")
    assert has_element?(view, "#not_runningcontainers_list_component", "api-stopped")

    assert has_element?(
             view,
             "#outdatedcontainers_list_component-rows[phx-update='stream']"
           )

    refute has_element?(view, "[id$='-manager']")
  end

  test "keeps the full container inventory visible in the compact tables", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, ContainersListHarness)

    headings = [
      "Priority",
      "Name",
      "Stack",
      "Image",
      "Size",
      "Pulled",
      "Build Date",
      "Resources",
      "Uptime"
    ]

    for heading <- headings do
      assert has_element?(
               view,
               "#outdatedcontainers_list_component-table th",
               heading
             )
    end

    assert has_element?(
             view,
             "#outdatedcontainers_list_component-rows tr",
             "api-outdated"
           )

    assert has_element?(
             view,
             "#outdatedcontainers_list_component-rows tr",
             "repo/api-outdated:latest"
           )

    assert has_element?(
             view,
             "#not_runningcontainers_list_component-table th",
             "Downtime"
           )
  end

  test "outdated container rows expose pull actions with node/image payloads", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, ContainersListHarness)

    view
    |> element("button[id$='-pull-image']")
    |> render_click()

    assert has_element?(
             view,
             "#last-containers-list-event",
             "image-pull:harness_node,repo/api-outdated:latest"
           )
  end
end
