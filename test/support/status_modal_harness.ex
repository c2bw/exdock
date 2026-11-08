defmodule ExdockWeb.StatusModalTest.StatusModalHarness do
  @moduledoc false

  use ExdockWeb, :live_view

  alias Exdock.Server.Logging.Status.Dashboard
  alias Exdock.Status.Dashboard.Row

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Phoenix.Component.assign(socket, last_event: "")}
  end

  @impl true
  def handle_event(event, _params, socket) do
    {:noreply, Phoenix.Component.assign(socket, :last_event, event)}
  end

  @impl true
  def render(assigns) do
    dash =
      Dashboard.new()
      |> Map.put(:node_refresh, %{"node-a" => Row.new({:error, :nodedown}, nil)})
      |> Map.put(:registry_fetch, %{"fetch-1" => Row.new({:ok, :requested}, %{fetched: 1, total: 2})})
      |> Map.put(:container_recreate, %{
        {:node_a, "api"} => Row.new({:ok, :requested}, nil) |> Row.put_message({:string, "Recreating"}),
        {:node_a, "warned-app"} =>
          Row.new({:warning, "Cleanup failed for warned-app-exdock-old-123"}, nil)
          |> Row.put_message({:string, "Recreated; cleanup failed for warned-app-exdock-old-123"})
      })

    assigns = Phoenix.Component.assign(assigns, :dash, dash)

    ~H"""
    <div id="status-modal-harness">
      <ExdockWeb.PageLive.StatusModal.render
        id="status-modal"
        dash={@dash}
        has_errors={true}
        errors_log={[{"2026-07-30 10:00:00", "fixture error"}]}
      />
      <p id="last-status-event">{@last_event}</p>
    </div>
    """
  end
end
