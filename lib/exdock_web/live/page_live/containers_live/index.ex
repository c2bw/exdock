defmodule ExdockWeb.ContainersLive.Index do
  @moduledoc """
  LiveView for the per-node containers page.

  The page renders a focused snapshot for one node while still subscribing to
  cluster-wide broadcasts. Incoming broadcasts are filtered down to the selected
  node so the table, summary, and sidebar stay current without reloading.
  """

  use ExdockWeb, :live_view

  use ExdockWeb.PageLive.LivePage.Use,
    title: "Containers",
    load: [:nodes, :repositories]

  alias Exdock.Configuration
  alias Exdock.ReadModel
  alias Exdock.ReadModel.NodePage
  alias ExdockWeb.PageLive.Utils.IdUtils
  alias ExdockWeb.PageLive.Utils.URLParam

  def load_page_context(%{"node_id" => encoded_node}, projections) do
    case route_node(encoded_node) do
      {:missing, nodename} ->
        page = ReadModel.page(projections)
        {page, %{nodename: nodename, node_detail: :not_found, nodes: page.nodes}}

      {:ok, nodename} ->
        {page, node_detail} = ReadModel.node_page(nodename, projections)
        {page, %{nodename: nodename, node_detail: node_detail, nodes: page.nodes}}
    end
  end

  def bootstrap_page(_params, _session, socket, %{
        nodename: nodename,
        node_detail: %ReadModel.Node{} = detail,
        nodes: nodes
      }) do
    case NodePage.initial(nodename, nodes, detail) do
      {:ok, assigns} -> assign(socket, assigns)
      :missing -> redirect_missing_node(socket, nodename)
    end
  end

  def bootstrap_page(_params, _session, socket, %{nodename: nodename, node_detail: :not_found}),
    do: redirect_missing_node(socket, nodename)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.operational_page
      id="containers-index"
      content_width={:wide}
      context={ExdockWeb.PageLive.LivePage.shell_context(assigns)}
    >
      <:aside>
        <ExdockWeb.ContainersLive.AsideUserInput.render
          id="aside-user-input"
          modals_to_render={@modals_to_render}
        />
        <ExdockWeb.HomepageLive.AsideContainerInfo.render
          id="aside-container-info"
          modals_to_render={@modals_to_render}
          log={@log}
          info={@node_info}
        />
      </:aside>

      <div class="w-full">
        <ExdockWeb.Commons.NodeSummary.render
          id={IdUtils.create_id("nodesummary#{@nodename}")}
          on_click={Phoenix.LiveView.JS.navigate("/")}
          nodename={@nodename}
          summary_type={:containers}
          node_settings={Configuration.node_settings(@server_configuration, @nodename)}
          node_metadata={@node.metadata}
          node_last_fetch={@node_last_fetch}
          containers={@containers_core}
          containers_extended={@containers_extended}
          node_info={@node_info}
          show_hardware_usage={true}
          clock_now={@page_clock_now}
        />
      </div>

      <div class="text-high-visibility h-full overflow-y-auto mb-48">
        <.live_component
          module={ExdockWeb.ContainersLive.ContainersList}
          id="containers_list_component"
          nodename={@nodename}
          containers={@containers_core}
          containers_extended={@containers_extended}
          active_modal_id={@active_modal_id}
          repositories={@repositories}
          clock_now={@page_clock_now}
          containers_revision={Map.fetch!(@event_revisions, :containers)}
        />
      </div>
    </Layouts.operational_page>
    """
  end

  def handle_page_broadcast(message, socket) do
    with {source, payload} when is_atom(source) <- message do
      case NodePage.broadcast_assigns(source, payload, socket.assigns.nodename) do
        {:ok, assigns} -> assign(socket, assigns)
        :unchanged -> socket
        :missing -> redirect_disconnected_node(socket)
        :unhandled -> :unhandled
      end
    else
      _message -> :unhandled
    end
  end

  defp redirect_disconnected_node(socket) do
    socket
    |> put_flash(:warning, "Node #{socket.assigns.nodename} disconnected.")
    |> push_navigate(to: "/")
  end

  defp route_node(encoded_node) do
    case URLParam.decode(encoded_node) do
      {:ok, node} ->
        {:ok, node}

      {:invalid, _} ->
        {:missing, "invalid node"}
    end
  end

  defp redirect_missing_node(socket, nodename) do
    socket
    |> put_flash(:warning, "Node #{nodename} disconnected.")
    |> push_navigate(to: "/")
  end
end
