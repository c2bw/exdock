defmodule ExdockWeb.StatusModalTest do
  use ExdockWeb.LiveCase

  import Phoenix.LiveViewTest

  alias ExdockWeb.StatusModalTest.StatusModalHarness

  test "clear-errors control emits the shared command event", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, StatusModalHarness)

    assert has_element?(view, "#clear-status-errors")
    assert has_element?(view, "#status-modal", "Nodes - Awaiting")
    assert has_element?(view, "#status-modal", "1 of 2 images processed")
    assert has_element?(view, "#status-modal", "Recreating")
    assert has_element?(view, "#status-modal tr.text-amber-600", "warned-app-exdock-old-123")

    view
    |> element("#clear-status-errors")
    |> render_click()

    assert has_element?(view, "#last-status-event", "clear_errors")
  end
end
