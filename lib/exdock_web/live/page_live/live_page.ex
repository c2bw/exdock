defmodule ExdockWeb.PageLive.LivePage do
  @moduledoc """
  Shared lifecycle for Exdock's server-backed LiveViews.

  Pages declare the projections they need and optionally override
  `bootstrap_page/4`, `handle_page_broadcast/2`, or `handle_page_event/3` for
  page-specific behavior.
  Connection gating, PubSub subscription, common assigns, render metrics, and
  generic broadcast reduction stay consistent in one place.
  """

  require Logger

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Exdock.{Events, Operations}
  alias Exdock.ReadModel.Projections
  alias ExdockWeb.PageLive.LivePage.ShellContext
  alias ExdockWeb.PageLive.Utils.{CommonBroadcastHandler, CommonPageHandler, RenderStatistics}

  @page_tick_interval 5_000

  @spec handle_event(binary(), any(), Phoenix.LiveView.Socket.t(), function()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event(event, params, socket, page_handler)
      when is_binary(event) and is_function(page_handler, 3) do
    socket =
      case page_handler.(event, params, socket) do
        :unhandled ->
          CommonPageHandler.handle(
            event,
            params,
            socket
          )

        %Phoenix.LiveView.Socket{} = updated_socket ->
          updated_socket
      end

    {:noreply, socket}
  end

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t(), keyword(), function(), function()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(params, session, socket, opts, bootstrap, context_loader)
      when is_list(opts) and is_function(bootstrap, 4) and is_function(context_loader, 2) do
    if Phoenix.LiveView.connected?(socket) do
      connected_mount(params, session, socket, opts, bootstrap, context_loader)
    else
      {:ok,
       assign(socket,
         page: "loading",
         page_clock_now: DateTime.utc_now()
       )}
    end
  end

  @spec handle_info(any(), Phoenix.LiveView.Socket.t(), function()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:gather_rendering_statistics, token}, socket, _page_handler) do
    case RenderStatistics.advance(socket.assigns.metrics_timer, token) do
      {:ok, timer} ->
        socket = assign(socket, :metrics_timer, timer)
        socket = CommonPageHandler.handle("gather_rendering_statistics", nil, socket)

        {:noreply, socket}

      :stale ->
        {:noreply, socket}
    end
  end

  def handle_info({:page_tick, token}, socket, _page_handler) do
    if is_reference(token) and token == Map.get(socket.assigns, :page_clock_token) do
      {:noreply, advance_page_clock(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(message, socket, page_handler) when is_function(page_handler, 2) do
    case normalize_runtime_event(message, socket) do
      {:stale, socket} ->
        {:noreply, socket}

      {:current, message, socket} ->
        case page_handler.(message, socket) do
          :unhandled -> {:noreply, CommonBroadcastHandler.handle(message, socket)}
          %Phoenix.LiveView.Socket{} = updated_socket -> {:noreply, updated_socket}
        end
    end
  end

  @type shell_context :: ShellContext.t()

  @doc "Builds the common rendering contract consumed by operational page layouts."
  @spec shell_context(map()) :: shell_context()
  defdelegate shell_context(assigns), to: ShellContext, as: :build

  defp normalize_runtime_event(
         {:exdock_event, _topic, revision, %{source: source, data: data}},
         socket
       )
       when is_atom(source) and is_integer(revision) do
    revisions = Map.get(socket.assigns, :event_revisions, %{})

    if revision > Map.get(revisions, source, -1) do
      socket = assign(socket, :event_revisions, Map.put(revisions, source, revision))
      {:current, {source, data}, socket}
    else
      {:stale, socket}
    end
  end

  defp normalize_runtime_event(message, socket), do: {:current, message, socket}

  defp connected_mount(params, session, socket, opts, bootstrap, context_loader) do
    projections = Keyword.get(opts, :load, [])

    case Events.subscribe_page(projections) do
      :ok ->
        {page, context} = load_context(params, projections, context_loader)
        maybe_refresh_cluster(page.user_settings, opts)

        socket =
          socket
          |> assign(Exdock.ReadModel.Page.to_assigns(page, projections))
          |> assign_page_defaults(Keyword.fetch!(opts, :title), page.user_settings, opts)

        socket = bootstrap.(params, session, socket, context)

        {:ok, socket}

      {:error, error} ->
        Logger.error("Failed to subscribe to Exdock events in #{inspect(socket.view)}: #{inspect(error)}")
        {:ok, assign(socket, :page, "error")}
    end
  end

  defp load_context(params, projections, context_loader) do
    case context_loader.(params, projections) do
      {%Exdock.ReadModel.Page{} = page, context} -> {page, context}
      %Exdock.ReadModel.Page{} = page -> {page, page}
    end
  end

  defp assign_page_defaults(socket, title, user_settings, opts) when is_binary(title) do
    socket
    |> assign(
      modals_to_render: %{},
      active_modal_id: nil,
      metrics_timer: RenderStatistics.set(nil, user_settings.rendering_statistics),
      server_render_time: nil,
      client_latency: nil,
      js_render_time: nil,
      event_revisions: initial_event_revisions(socket.assigns),
      settings_import_form: settings_import_form(socket.assigns.server_configuration),
      page_title: title,
      page: "loaded"
    )
    |> initialize_page_clock(Keyword.get(opts, :clock, true))
  end

  defp initialize_page_clock(socket, true), do: advance_page_clock(socket)

  defp initialize_page_clock(socket, false) do
    assign(socket,
      page_clock_now: DateTime.utc_now(),
      page_clock_token: nil
    )
  end

  defp advance_page_clock(socket) do
    token = make_ref()
    Process.send_after(self(), {:page_tick, token}, @page_tick_interval)

    assign(socket,
      page_clock_now: DateTime.utc_now(),
      page_clock_token: token
    )
  end

  defp initial_event_revisions(assigns) do
    runtime_revision = Map.get(assigns, :runtime_revision, 0)
    activity_revision = Map.get(assigns, :activity_revision, 0)

    Projections.initial_revisions(runtime_revision, activity_revision)
  end

  defp maybe_refresh_cluster(user_settings, opts) do
    if Keyword.get(opts, :refresh_cluster, false) and user_settings.pageload_node_refresh do
      Operations.refresh_cluster()
    else
      :ok
    end
  end

  defp settings_import_form(configuration) do
    Phoenix.Component.to_form(%{
      "server_configuration" => Exdock.Configuration.to_json(configuration)
    })
  end
end
