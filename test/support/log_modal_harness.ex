defmodule ExdockWeb.LogModalHarness do
  use ExdockWeb, :live_view

  alias Exdock.Server.Logging.Log

  @impl true
  def mount(_params, _session, socket) do
    timestamp = ~U[2026-01-01 00:00:00Z]

    logs = [
      %Log{id: "visible-log", message_id: :node_connected, message_data: "node-a", start_time: timestamp},
      %Log{
        id: "hidden-log",
        message_id: :node_connected,
        message_data: "node-b",
        start_time: timestamp,
        hidden: true
      }
    ]

    {:ok, Phoenix.Component.assign(socket, :logs, logs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={ExdockWeb.PageLive.LogModal}
      id="log-modal"
      render?={true}
      log={@logs}
    />
    """
  end
end
