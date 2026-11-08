defmodule ExdockWeb.AutomationPrioritiesSettingsTest.ControlsHarness do
  @moduledoc false

  use ExdockWeb, :live_view

  alias Exdock.Domain
  alias Exdock.{Operations, Schedule}
  alias ExdockWeb.TestFixtures.Container, as: ContainerFixture
  alias ExdockWeb.PageLive.Utils.LiveOperation

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     Phoenix.Component.assign(socket,
       user_settings: %Domain.UserSettings{
         automation_enabled: false,
         auto_update_releases: true,
         auto_update_containers: true,
         auto_update_above: 2,
         cron_string: "0 22 * * *"
       },
       containers: %{
         "node_a" => [
           ContainerFixture.read_model(
             name: "api",
             image_status: :outdated,
             auto_update: :passthrough,
             priority: 4
           ),
           ContainerFixture.read_model(
             name: "worker",
             image_status: :updated,
             auto_update: :passthrough,
             priority: 3
           )
         ]
       },
       flash_event: "",
       last_user_setting_event: "",
       cron_form: Phoenix.Component.to_form(%{"cron_string" => ""}),
       clock_now: ~U[2026-01-01 20:00:00Z]
     )}
  end

  @impl true
  def handle_event("change_user_settings", params, socket) do
    event = "#{params["key"]}:#{params["val"]}"
    {:noreply, Phoenix.Component.assign(socket, :last_user_setting_event, event)}
  end

  def handle_event("registry_fetch", _params, socket), do: {:noreply, socket}
  def handle_event("node_refresh_cluster", _params, socket), do: {:noreply, socket}

  def handle_event("set_cron", %{"cron_string" => cron_string}, socket)
      when is_binary(cron_string) do
    socket =
      if Schedule.valid?(cron_string) do
        LiveOperation.handle(socket, Operations.set_cron_string(cron_string))
      else
        Phoenix.Component.assign(socket, :flash_event, "Cron string is invalid")
      end

    {:noreply, socket}
  end

  def handle_event("set_cron", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, :flash_event, "Invalid cron request")}

  def handle_event("run_automation", _params, socket),
    do: {:noreply, LiveOperation.handle(socket, Operations.run_automation())}

  @impl true
  def handle_info({:update_flash, {_kind, message}}, socket) do
    {:noreply, Phoenix.Component.assign(socket, :flash_event, message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="controls-harness">
      <ExdockWeb.Automation.Settings.render
        id="automation-settings"
        user_settings={@user_settings}
        clock_now={@clock_now}
        cron_form={@cron_form}
      />
      <.live_component
        module={ExdockWeb.Automation.Containers}
        id="automation-containers"
        containers={@containers}
        required_priority={@user_settings.auto_update_above}
      />
      <.live_component
        module={ExdockWeb.ContainersPriorities.Containers}
        id="priorities-containers"
        containers={@containers}
      />
      <p id="flash-event">{@flash_event}</p>
      <p id="last-user-setting-event">{@last_user_setting_event}</p>
    </div>
    """
  end
end
