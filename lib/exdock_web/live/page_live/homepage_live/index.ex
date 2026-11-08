defmodule ExdockWeb.HomepageLive.Index do
  @moduledoc """
  LiveView for the cluster homepage.

  The homepage shows aggregate node/container/image status, subscribes to the
  shared Exdock PubSub topic, and translates top-level container/image actions
  into jobs for the server dispatcher.
  """

  use ExdockWeb, :live_view

  use ExdockWeb.PageLive.LivePage.Use,
    title: "Home",
    load: [:nodes, :containers, :repositories, :cluster_info],
    refresh_cluster: true

  alias ExdockWeb.PageLive.Utils.IdUtils
  alias ExdockWeb.PageLive.Utils.URLParam
  alias Exdock.ReadModel.Projections
  alias Exdock.Configuration
  alias Exdock.Datetime
  alias ExdockWeb.HomepageLive.Presentation

  def bootstrap_page(_params, _session, socket, page) do
    assign(
      socket,
      :homepage_presentation,
      Presentation.build(page.cluster_info, page.containers_extended)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.operational_page
      id="homepage-index"
      content_width={:wide}
      context={ExdockWeb.PageLive.LivePage.shell_context(assigns)}
    >
      <:aside>
        <ExdockWeb.HomepageLive.AsideUserInput.render
          id="aside-user-input"
          modals_to_render={@modals_to_render}
          active_modal_id={@active_modal_id}
          containers={@containers}
          containers_revision={@runtime_revision}
          containers_extended={@containers_extended}
          repositories={@repositories}
          clock_now={@page_clock_now}
        />
        <ExdockWeb.HomepageLive.AsideContainerInfo.render
          id="aside-container-info"
          modals_to_render={@modals_to_render}
          log={@log}
          info={@cluster_info.info}
        />
      </:aside>

      <div class="text-high-visibility h-full overflow-y-auto mb-48">
        <ul class="space-y-1 mb-8">
          <%!-- Node Level --%>
          <%= for {nodename, node_info} <- @homepage_presentation.node_rows do %>
            <div class="w-full space-x-4">
              <li class="overflow-hidden">
                <ExdockWeb.Commons.NodeSummary.render
                  id={IdUtils.create_id("nodesummary#{nodename}")}
                  on_click={Phoenix.LiveView.JS.navigate("/containers/#{URLParam.encode(nodename)}")}
                  modals_to_render={@modals_to_render}
                  summary_type={:containers}
                  nodename={nodename}
                  node_settings={Configuration.node_settings(@server_configuration, nodename)}
                  node_last_fetch={@nodes |> Datetime.get_node_last_fetch(nodename)}
                  node_info={node_info}
                  containers_extended={@containers_extended |> Map.get(nodename, %{})}
                  resource_rows={Map.get(@homepage_presentation.resource_rows, nodename, [])}
                  clock_now={@page_clock_now}
                />
              </li>
            </div>
          <% end %>
        </ul>
      </div>
    </Layouts.operational_page>
    """
  end

  def handle_page_broadcast({:cluster_info, payload}, socket) do
    {:ok, %{cluster_info: cluster_info}} = Projections.broadcast_assigns(:cluster_info, payload)

    assign(socket,
      cluster_info: cluster_info,
      homepage_presentation: Presentation.with_cluster_info(socket.assigns.homepage_presentation, cluster_info)
    )
  end

  def handle_page_broadcast({:containers, payload}, socket) do
    {:ok, container_assigns} = Projections.broadcast_assigns(:containers, payload)

    socket
    |> assign(container_assigns)
    |> assign(
      :homepage_presentation,
      Presentation.with_containers(
        socket.assigns.homepage_presentation,
        container_assigns.containers_extended
      )
    )
  end

  def handle_page_broadcast(_message, _socket), do: :unhandled
end
