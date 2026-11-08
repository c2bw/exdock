defmodule ExdockWeb.LivePageTest do
  use ExdockWeb.LiveCase

  import Phoenix.LiveViewTest

  alias ExdockWeb.LivePageTest.LifecycleHarness

  test "bootstraps common assigns and requested projections", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, LifecycleHarness)

    assert has_element?(view, "#lifecycle-harness")
    assert has_element?(view, "#lifecycle-title", "Lifecycle probe")
    assert has_element?(view, "#lifecycle-node-count", "0")
    assert has_element?(view, "#lifecycle-container-count", "0")
    assert has_element?(view, "#lifecycle-images-loaded", "false")
  end

  test "routes page-specific messages before reducing shared broadcasts", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, LifecycleHarness)

    send(view.pid, {:page_probe, "handled locally"})
    assert has_element?(view, "#lifecycle-page-probe", "handled locally")

    Exdock.Events.publish(:activity, %{source: :status, data: :broadcast_ready})
    assert has_element?(view, "#lifecycle-status", ":broadcast_ready")

    Exdock.Events.publish(:cluster, %{source: :images, data: %{}})
    assert has_element?(view, "#lifecycle-images-loaded", "true")
  end

  test "ignores stale source revisions without rejecting sibling projections", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, LifecycleHarness)

    send(view.pid, {:exdock_event, :activity, 10_000, %{source: :status, data: :current}})
    assert has_element?(view, "#lifecycle-status", ":current")

    send(view.pid, {:exdock_event, :activity, 9_999, %{source: :status, data: :stale}})
    assert has_element?(view, "#lifecycle-status", ":current")

    send(view.pid, {:exdock_event, :cluster, 10_000, %{source: :images, data: %{}}})
    assert has_element?(view, "#lifecycle-images-loaded", "true")
  end

  test "builds the operational shell contract with stable defaults" do
    context =
      ExdockWeb.PageLive.LivePage.shell_context(%{
        page: "loaded",
        flash: %{"info" => "ready"},
        current_user: %{email: "admin@example.com"},
        status: :ready
      })

    assert %ExdockWeb.PageLive.LivePage.ShellContext{} = context
    assert context.page == "loaded"
    assert context.flash == %{"info" => "ready"}
    assert context.current_user == %{email: "admin@example.com"}
    assert context.status == :ready
    assert context.modals_to_render == %{}
    assert context.nodes_list == []
    refute Map.has_key?(context, :show_default_priorities)
  end

  test "advances one page clock and ignores stale tick tokens" do
    token = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        page_clock_token: token,
        page_clock_now: ~U[2026-01-01 00:00:00Z]
      }
    }

    assert {:noreply, advanced} =
             ExdockWeb.PageLive.LivePage.handle_info(
               {:page_tick, token},
               socket,
               fn _message, _socket -> :unhandled end
             )

    assert advanced.assigns.page_clock_token != token
    assert DateTime.after?(advanced.assigns.page_clock_now, socket.assigns.page_clock_now)

    assert {:noreply, unchanged} =
             ExdockWeb.PageLive.LivePage.handle_info(
               {:page_tick, token},
               advanced,
               fn _message, _socket -> :unhandled end
             )

    assert unchanged == advanced
  end
end
