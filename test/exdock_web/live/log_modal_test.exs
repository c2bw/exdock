defmodule ExdockWeb.LogModalTest do
  use ExdockWeb.LiveCase

  import Phoenix.LiveViewTest

  alias ExdockWeb.LogModalHarness

  test "streams visible detailed log entries", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, LogModalHarness)

    assert has_element?(view, "#log-modal-entries[phx-update='stream']")
    assert has_element?(view, "#log_entries-visible-log")
    refute has_element?(view, "#log_entries-hidden-log")
  end
end
