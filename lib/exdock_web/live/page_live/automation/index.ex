defmodule ExdockWeb.Automation.Index do
  @moduledoc """
  LiveView for automation settings and scheduled update controls.

  This page exposes user-configurable automation thresholds and container
  selection while the actual periodic execution remains in server state.
  """

  use ExdockWeb, :live_view

  use ExdockWeb.PageLive.LivePage.Use,
    title: "Automation",
    load: [:nodes, :containers]

  alias Exdock.{Operations, Schedule}
  alias ExdockWeb.PageLive.Utils.LiveOperation

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.operational_page
      id="automation-index"
      content_width={:wide}
      context={ExdockWeb.PageLive.LivePage.shell_context(assigns)}
    >
      <:aside>
        <ExdockWeb.Automation.AsideUserInput.render id="aside-user-input" />
        <div class="flex flex-grow items-end"></div>
        <ExdockWeb.PageLive.Log.render id="aside-container-log" modals_to_render={@modals_to_render} log={@log} />
      </:aside>

      <div class="w-full">
        <ExdockWeb.Automation.Settings.render
          id="automation-settings"
          user_settings={@server_configuration.user_settings}
          clock_now={@page_clock_now}
          cron_form={@cron_form}
        />
      </div>

      <div class="w-full">
        <.live_component
          module={ExdockWeb.Automation.Containers}
          id="automation-containers"
          containers={@containers}
          required_priority={@server_configuration.user_settings.auto_update_above}
        />
      </div>
    </Layouts.operational_page>
    """
  end

  def bootstrap_page(_params, _session, socket, _context) do
    assign(socket, :cron_form, to_form(%{"cron_string" => ""}))
  end

  def handle_page_event("set_cron", %{"cron_string" => cron_string}, socket)
      when is_binary(cron_string) do
    if Schedule.valid?(cron_string) do
      LiveOperation.handle(socket, Operations.set_cron_string(cron_string))
    else
      LiveOperation.invalid(socket, "Cron string is invalid")
    end
  end

  def handle_page_event("set_cron", _params, socket),
    do: LiveOperation.invalid(socket, "Invalid cron request")

  def handle_page_event("run_automation", _params, socket),
    do: LiveOperation.handle(socket, Operations.run_automation())

  def handle_page_event(_event, _params, _socket), do: :unhandled
end
