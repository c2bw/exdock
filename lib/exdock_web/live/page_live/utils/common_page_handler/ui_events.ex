defmodule ExdockWeb.PageLive.Utils.CommonPageHandler.UiEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Exdock.{Operations, Telemetry}
  alias ExdockWeb.PageLive.Utils.{LiveOperation, RenderStatistics}

  @spec handle(binary(), any(), Phoenix.LiveView.Socket.t()) ::
          {:handled, Phoenix.LiveView.Socket.t()} | :unhandled
  def handle(event, params, socket) do
    case {event, params} do
      {"show_lazy_modal", %{"modal_id" => modal_id}} ->
        handled(show_lazy_modal(socket, modal_id))

      {"hide_lazy_modal", %{"modal_id" => modal_id}} ->
        handled(hide_lazy_modal(socket, modal_id))

      {"toggle_rendering_statistics", %{"key" => key, "val" => value}} ->
        handled(toggle_rendering_statistics(socket, key, value))

      {"renderstats:js", %{"time" => js_render_time}} ->
        handled(assign(socket, js_render_time: js_render_time))

      {"renderstats:pong", %{"ping_id" => ping_id}} ->
        handled(renderstats_pong(socket, ping_id))

      {"gather_rendering_statistics", _} ->
        handled(gather_rendering_statistics(socket))

      _ ->
        :unhandled
    end
  end

  defp show_lazy_modal(socket, modal_id) do
    modals = Map.get(socket.assigns, :modals_to_render, %{})

    assign(socket,
      modals_to_render: Map.put(modals, modal_id, true),
      active_modal_id: modal_id
    )
  end

  defp hide_lazy_modal(socket, modal_id) do
    active_modal_id = Map.get(socket.assigns, :active_modal_id)

    assign(socket,
      modals_to_render:
        socket.assigns
        |> Map.get(:modals_to_render, %{})
        |> Map.delete(modal_id),
      active_modal_id: if(active_modal_id == modal_id, do: nil, else: active_modal_id)
    )
  end

  defp toggle_rendering_statistics(socket, key, value) do
    socket =
      assign(
        socket,
        :metrics_timer,
        RenderStatistics.set(socket.assigns.metrics_timer, value == "true")
      )

    LiveOperation.handle(socket, Operations.change_user_setting(key, value))
  end

  defp gather_rendering_statistics(socket) do
    server_render_time =
      case Telemetry.measurement([:phoenix, :live_view, :render, :stop]) do
        {:ok, %{measurements: _, average: average}} -> average
        {:error, _reason} -> nil
      end

    socket
    |> assign(server_render_time: server_render_time)
    |> Phoenix.LiveView.push_event("renderstats:ping", %{
      ping_id: System.monotonic_time(:millisecond)
    })
    |> Phoenix.LiveView.push_event("renderstats:js", %{})
  end

  defp renderstats_pong(socket, ping_id) when is_integer(ping_id),
    do: assign(socket, :client_latency, System.monotonic_time(:millisecond) - ping_id)

  defp renderstats_pong(socket, _ping_id), do: socket
  defp handled(socket), do: {:handled, socket}
end
