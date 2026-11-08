defmodule ExdockWeb.AutomationPrioritiesSettingsTest.SettingsHarness do
  @moduledoc false

  use ExdockWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    page = Exdock.ReadModel.page([])

    {:ok,
     Phoenix.Component.assign(socket,
       last_event: "",
       server_configuration: page.server_configuration,
       settings_import_form: Phoenix.Component.to_form(%{"server_configuration" => ""})
     )}
  end

  @impl true
  def handle_event(event, params, socket) do
    {:noreply, Phoenix.Component.assign(socket, :last_event, "#{event}:#{params["key"] || "submit"}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="settings-harness">
      <ExdockWeb.PageLive.SettingsPage.render
        id="settings-page-component"
        configuration_form={@settings_import_form}
        render?={true}
        server_configuration={@server_configuration}
      />
      <p id="last-settings-event">{@last_event}</p>
    </div>
    """
  end
end
