defmodule ExdockWeb.ContainersLive.ManagerTest do
  use ExdockWeb.LiveCase

  import Phoenix.LiveViewTest

  alias ExdockWeb.ContainersLiveTest.ContainerManagerHarness

  test "container manager renders lifecycle forms and forwards submits", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, ContainerManagerHarness)

    assert has_element?(view, "#container-manager-harness", "Container Manager")
    assert has_element?(view, "#container-manager-modal[phx-mounted]")
    assert has_element?(view, "#container-manager-modal-container.container-manager-modal")
    assert has_element?(view, "#container-manager-componentscroll-region")
    refute has_element?(view, "#container-manager-modal-content [phx-mounted]")
    assert has_element?(view, "#container-manager-componentheader-auto-update span.w-20.min-w-20")
    assert has_element?(view, "#container-manager-componentheader-priority span.w-8")
    assert has_element?(view, "p.text-center", "Auto update")
    assert has_element?(view, "p.text-center", "Priority")
    assert has_element?(view, "form[phx-submit='container-stop']")
    assert has_element?(view, "form[phx-submit='container-restart']")
    assert has_element?(view, "form[phx-submit='container-recreate']")
    assert has_element?(view, "form[phx-submit='image-pull']")

    assert has_element?(
             view,
             "#container-manager-componentconfigurationraw_inspect_details"
           )

    assert has_element?(
             view,
             "#container-manager-componentconfigurationlogs_details"
           )

    assert has_element?(view, "#container-manager-componentconfiguration-logs-form")
    assert has_element?(view, "form[phx-submit='repository-url-update']")
    assert has_element?(view, "#container-manager-componentrepository-override")
    assert has_element?(view, "#container-manager-componentrepository-url-form")

    assert has_element?(
             view,
             "#container-manager-componentrepository-current-url[href='https://github.com/example/api']"
           )

    assert has_element?(view, "#container-manager-componentreleases-panel")

    assert has_element?(
             view,
             "#container-manager-componentreleases-refresh[aria-label='Refresh releases']"
           )

    assert has_element?(
             view,
             "#container-manager-componentstatus-local-digest",
             "sha256:local-api-digest"
           )

    refute has_element?(view, "#container-manager-componentstatus-remote-digest")

    assert has_element?(view, "#container-manager-componentstatus-runtime-duration", "1s")
    assert has_element?(view, "#container-manager-componentconfiguration-table-uptime", "1s")

    send(view.pid, :advance_clock)

    assert has_element?(view, "#container-manager-componentstatus-runtime-duration", "1h")
    assert has_element?(view, "#container-manager-componentconfiguration-table-uptime", "1h")

    view
    |> form("#container-manager-componentrecreate-options-form", %{"image_pull" => "true"})
    |> render_change()

    assert has_element?(view, "#container-manager-componentrecreate_pull_image[checked]")
    assert has_element?(view, "#container-manager-componentrecreate_pull_image.container-manager-pull-checkbox")

    send(view.pid, :refresh_container_manager)

    assert has_element?(view, "#container-manager-componentrecreate_pull_image[checked]")
    assert has_element?(view, "#container-manager-componentrecreate_pull_image_value[value='true']")

    view |> form("#container-manager-componentrecreate-form") |> render_submit()

    assert has_element?(
             view,
             "#last-container-manager-event",
             "container-recreate:harness_node,api"
           )

    view |> form("#container-manager-componentconfiguration-logs-form") |> render_submit()
    assert has_element?(view, "#last-container-manager-event", "container-logs:api")

    view |> form("form[phx-submit='image-pull']") |> render_submit()

    assert has_element?(
             view,
             "#last-container-manager-event",
             "image-pull:harness_node,repo/api:latest"
           )
  end

  test "forwards every lifecycle form with the selected container", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, ContainerManagerHarness)

    view |> form("#container-manager-componentstop-form") |> render_submit()
    assert has_element?(view, "#last-container-manager-event", "container-stop:api")

    view |> form("#container-manager-componentrestart-form") |> render_submit()
    assert has_element?(view, "#last-container-manager-event", "container-restart:api")

    send(view.pid, :stop_container)

    assert has_element?(view, "#container-manager-componentstart-form button:not([disabled])")

    view |> form("#container-manager-componentstart-form") |> render_submit()
    assert has_element?(view, "#last-container-manager-event", "container-start:api")
  end

  test "forwards repository and header actions with their field values", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, ContainerManagerHarness)

    view
    |> form("#container-manager-componentrepository-url-form", %{
      "img_name" => "repo/api:latest",
      "new_url" => "https://github.com/example/new-api"
    })
    |> render_submit()

    assert has_element?(
             view,
             "#last-container-manager-event",
             "repository-url-update:https://github.com/example/new-api"
           )

    view
    |> element("#container-manager-componentheader-refresh")
    |> render_click()

    assert has_element?(view, "#last-container-manager-event", "node_refresh:harness_node")
  end

  test "container policy controls remain owned by the manager component", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, ContainerManagerHarness)

    view
    |> element("#container-manager-componentheader-priority button[phx-click='change_priority'][phx-value-priority='4']")
    |> render_click()

    view
    |> element("#container-manager-componentheader-auto-update button[phx-click='change_auto_update'][phx-value-next='next']")
    |> render_click()

    assert has_element?(view, "#container-manager-componentheader-identity")
  end

  test "refreshes releases and expands the complete release history", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, ContainerManagerHarness)

    assert has_element?(view, "#container-manager-componentreleases-panel", "v2.0.0")
    refute has_element?(view, "#container-manager-componentreleases-panel", "v1.0.0")

    view
    |> element("#container-manager-componentreleases-refresh")
    |> render_click()

    assert has_element?(view, "#container-manager-componentreleases-panel")

    view
    |> element("#container-manager-componentreleases-show-all")
    |> render_click()

    assert has_element?(view, "#container-manager-componentreleases-panel", "v1.0.0")
    refute has_element?(view, "#container-manager-componentreleases-show-all")
  end

  test "shows the remote digest only for running containers that are not up to date", %{
    conn: conn
  } do
    {:ok, view, _html} = live_isolated(conn, ContainerManagerHarness)

    refute has_element?(view, "#container-manager-componentstatus-remote-digest")

    send(view.pid, :show_outdated_digest)

    assert has_element?(
             view,
             "#container-manager-componentstatus-remote-digest",
             "sha256:remote-api-digest"
           )

    send(view.pid, :stop_container)

    refute has_element?(view, "#container-manager-componentstatus-remote-digest")

    assert has_element?(
             view,
             "#container-manager-componentstatus-local-digest",
             "sha256:local-api-digest"
           )
  end
end
