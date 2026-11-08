defmodule ExdockWeb.CommonPageHandlerTest.HandlerHarness do
  @moduledoc false

  use ExdockWeb, :live_view

  alias ExdockWeb.PageLive.Utils.{CommonPageHandler, LiveOperation}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     Phoenix.Component.assign(socket,
       modals_to_render: %{},
       active_modal_id: nil,
       metrics_timer: nil
     )}
  end

  @impl true
  def handle_event("reject_operation", _params, socket) do
    {:noreply, LiveOperation.handle(socket, {:error, :runtime_busy})}
  end

  def handle_event(event, params, socket) do
    {:noreply, CommonPageHandler.handle(event, params, socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="common-page-handler-harness">
        <button id="show-settings-modal" phx-click="show_lazy_modal" phx-value-modal_id="settings-page">show</button>
        <button
          id="enable-rendering-statistics"
          phx-click="toggle_rendering_statistics"
          phx-value-key="rendering_statistics"
          phx-value-val="true"
        >
          enable metrics
        </button>
        <button id="bad-config-import" phx-click="import_server_configuration" phx-value-server_configuration="{bad">bad import</button>
        <button id="reject-operation" phx-click="reject_operation">reject</button>
        <p id="settings-modal-rendered">{Map.get(@modals_to_render, "settings-page", false)}</p>
        <p id="active-modal-id">{@active_modal_id}</p>
        <p id="rendering-statistics-enabled">{not is_nil(@metrics_timer)}</p>
      </div>
    </Layouts.app>
    """
  end
end
