defmodule ExdockWeb.AutomationPrioritiesSettingsTest do
  use ExdockWeb.LiveCase

  import Phoenix.LiveViewTest

  alias ExdockWeb.AutomationPrioritiesSettingsTest.{ControlsHarness, SettingsHarness}

  test "exhausted automation schedules display no future runs" do
    document =
      render_component(&ExdockWeb.Automation.Settings.render/1, %{
        id: "automation-settings",
        user_settings: %Exdock.Domain.UserSettings{cron_string: "0 0 1 1 * 2025"},
        clock_now: ~U[2026-01-01 00:00:00Z],
        cron_form: Phoenix.Component.to_form(%{"cron_string" => ""})
      })
      |> LazyHTML.from_fragment()

    assert LazyHTML.query(document, "#automation-next-run") |> LazyHTML.text() =~ "No future runs"
  end

  describe "missing LiveView routes" do
    test "mounts automation and priorities pages with shared controls", %{conn: conn} do
      for {path, prefix, page_id} <- [
            {~p"/automation", "automation", "automation-index"},
            {~p"/priorities", "priorities", "containers-priorities-index"}
          ] do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(view, "#app-shell")
        assert has_element?(view, "##{page_id}")
        assert has_element?(view, "aside")
        assert has_element?(view, "##{prefix}-registry-fetch-button")
        assert has_element?(view, "##{prefix}-node-refresh-button")
        assert has_element?(view, "#about-page")
        assert has_element?(view, "#settings-page")
      end
    end
  end

  describe "settings modal" do
    test "renders user settings, nested managers, and import form", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, SettingsHarness)

      assert has_element?(view, "#settings-harness")
      assert has_element?(view, "#settings-page-component")
      assert has_element?(view, "#settings-preferences")
      assert has_element?(view, "#settings-management")
      assert has_element?(view, "#settings-server-configuration")
      assert has_element?(view, "button[phx-click='change_user_settings'][phx-value-key='pageload_node_refresh']")
      assert has_element?(view, "button[phx-click='toggle_rendering_statistics'][phx-value-key='rendering_statistics']")
      assert has_element?(view, "#settings-toggle-pageload_node_refresh[aria-pressed]")
      assert has_element?(view, "#manage-repositories-overrides")
      assert has_element?(view, "#manage-container-priorities-link[href='/priorities']")
      assert has_element?(view, "#server-configuration-import-form")
      assert has_element?(view, "#server_configuration_textarea")
      assert has_element?(view, "#import-server-configuration-button")
    end

    test "settings controls emit parent LiveView events", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, SettingsHarness)

      for {event, key} <- [
            {"change_user_settings", "pageload_node_refresh"},
            {"change_user_settings", "container_resources"},
            {"toggle_rendering_statistics", "rendering_statistics"},
            {"change_user_settings", "automation_enabled"}
          ] do
        view
        |> element("button[phx-click='#{event}'][phx-value-key='#{key}']")
        |> render_click()

        assert has_element?(view, "#last-settings-event", "#{event}:#{key}")
      end
    end

    test "server configuration form emits its complete JSON payload", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, SettingsHarness)

      configuration =
        Exdock.Configuration.to_json(Exdock.ReadModel.page([]).server_configuration)

      view
      |> form("#server-configuration-import-form", %{"server_configuration" => configuration})
      |> render_submit()

      assert has_element?(view, "#last-settings-event", "import_server_configuration:submit")
    end
  end

  describe "automation and priorities controls" do
    test "automation settings validate cron input and render run controls", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ControlsHarness)

      assert has_element?(view, "#automation-settings-cron-form")
      assert has_element?(view, "#cron_input_string")
      assert has_element?(view, "span[phx-click='run_automation']", "run")
      assert has_element?(view, "#automation-settings-toggle-automation_enabled[aria-pressed]")
      assert has_element?(view, "#automation-settings-toggle-auto_update_releases[aria-pressed]")
      assert has_element?(view, "#automation-settings-toggle-auto_update_containers[aria-pressed]")
      assert has_element?(view, ".automation-info", "2h from now")

      view
      |> form("#automation-settings-cron-form", %{cron_string: "not a cron"})
      |> render_submit()

      assert has_element?(view, "#flash-event", "Cron string is invalid")
    end

    test "automation settings persist valid cron input", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ControlsHarness)
      subscribe_to_operations!()

      view
      |> form("#automation-settings-cron-form", %{cron_string: "0 6 * * *"})
      |> render_submit()

      assert %{status: :completed} = await_operation!(:change_user_setting)
      assert Exdock.ReadModel.page([]).user_settings.cron_string == "0 6 * * *"
      refute has_element?(view, "#flash-event", "Cron string is invalid")
    end

    test "automation toggles and threshold controls emit canonical setting values", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ControlsHarness)

      for {selector, expected} <- [
            {"#automation-settings-toggle-automation_enabled", "automation_enabled:true"},
            {"#automation-settings-toggle-auto_update_releases", "auto_update_releases:false"},
            {"#automation-settings-toggle-auto_update_containers", "auto_update_containers:false"},
            {"button[aria-label='Decrease priority threshold']", "auto_update_above:1"},
            {"button[aria-label='Increase priority threshold']", "auto_update_above:3"}
          ] do
        view |> element(selector) |> render_click()
        assert has_element?(view, "#last-user-setting-event", expected)
      end
    end

    test "run now control starts the automation operation", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ControlsHarness)
      subscribe_to_operations!()

      view
      |> element("span[phx-click='run_automation']")
      |> render_click()

      assert %{status: :completed} = await_operation!(:run_automation)
      assert has_element?(view, "#controls-harness")
    end

    test "automation and priority rows render and accept update clicks", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ControlsHarness)

      assert has_element?(view, "td", "node_a")
      assert has_element?(view, "td", "api")
      assert has_element?(view, "#automation-container-rows[phx-update='stream']")
      assert has_element?(view, "#priority-container-rows[phx-update='stream']")
      assert has_element?(view, "button[phx-click='change_auto_update'][phx-value-container='api']")
      assert has_element?(view, "button[phx-click='change_priority'][phx-value-container='api']")

      view
      |> element("button[phx-click='change_auto_update'][phx-value-container='api'][phx-value-next='next']")
      |> render_click()

      view
      |> element("button[phx-click='change_priority'][phx-value-container='api'][phx-value-priority='5']")
      |> render_click()

      assert has_element?(view, "#controls-harness")
    end

    test "priority table can hide and show default priority rows", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ControlsHarness)

      assert has_element?(view, "button[phx-click='toggle_default_priorities_visibility']", "showing default")
      assert has_element?(view, "#priority-container-rows td", "worker")

      view
      |> element("button[phx-click='toggle_default_priorities_visibility']")
      |> render_click()

      assert has_element?(view, "button[phx-click='toggle_default_priorities_visibility']", "hiding default")
      refute has_element?(view, "#priority-container-rows td", "worker")

      view
      |> element("button[phx-click='toggle_default_priorities_visibility']")
      |> render_click()

      assert has_element?(view, "#priority-container-rows td", "worker")
    end

    test "malformed component priority data is rejected without terminating the parent LiveView", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ControlsHarness)

      view
      |> element("button[phx-click='change_priority'][phx-value-container='api'][phx-value-priority='5']")
      |> render_click(%{"priority" => "not-a-priority"})

      assert has_element?(view, "#controls-harness")
      assert has_element?(view, "#flash-event", "Priority must be between 1 and 5")
    end

    test "malformed auto-update data is rejected without terminating the parent LiveView", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ControlsHarness)

      view
      |> element("button[phx-click='change_auto_update'][phx-value-container='api'][phx-value-next='next']")
      |> render_click(%{"current-policy" => "unknown"})

      assert has_element?(view, "#controls-harness")
      assert has_element?(view, "#flash-event", "Invalid auto-update request")
    end
  end
end
