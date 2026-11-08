defmodule ExdockWeb.ImagesLive.Index do
  @moduledoc """
  LiveView for cluster image inventory and registry actions.

  It combines per-node image lists with repository/tag metadata and dispatches
  image pull/delete/fetch actions into the job system.
  """

  use ExdockWeb, :live_view

  use ExdockWeb.PageLive.LivePage.Use,
    title: "Images",
    load: [:nodes, :images, :cluster_info],
    refresh_cluster: true

  alias Exdock.Configuration
  alias Exdock.Datetime
  alias Exdock.ReadModel.{Image, Projections}
  alias ExdockWeb.ImagesLive.Presentation
  alias ExdockWeb.PageLive.Utils.IdUtils

  def bootstrap_page(_params, _session, socket, %{images: images, cluster_info: cluster_info}) do
    socket
    |> assign_image_data(images)
    |> assign(:image_node_rows, Presentation.node_rows(cluster_info))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.operational_page
      id="images-index"
      content_id="images-live-page"
      content_width={:compact}
      context={ExdockWeb.PageLive.LivePage.shell_context(assigns)}
    >
      <:aside>
        <ExdockWeb.ImagesLive.AsideUserInput.render
          id="aside-user-input"
          registries={@image_presentation.registries}
        />
        <ExdockWeb.ImagesLive.AsideImageInfo.render
          id="aside-image-info"
          modals_to_render={@modals_to_render}
          summary={@image_presentation.summary}
          log={@log}
        />
      </:aside>

      <div class="text-high-visibility h-full overflow-y-auto mb-48">
        <ul class="space-y-1 mb-8">
          <%!-- Node Level --%>
          <%= for {nodename, info} <- @image_node_rows do %>
            <ExdockWeb.Commons.NodeSummary.render
              id={IdUtils.create_id("nodesummary#{nodename}")}
              on_click={show_modal(IdUtils.create_id("nodeimagesmodal#{nodename}"))}
              summary_type={:images}
              nodename={nodename}
              node_settings={Configuration.node_settings(@server_configuration, nodename)}
              node_last_fetch={@nodes |> Datetime.get_node_last_fetch(nodename)}
              node_info={info}
              clock_now={@page_clock_now}
            />
          <% end %>
        </ul>
      </div>

      <%= for {nodename, info} <- @image_node_rows do %>
        <.modal id={IdUtils.create_id("nodeimagesmodal#{nodename}")} max_width="max-w-7xl">
          <.live_component
            module={ExdockWeb.ImagesLive.NodeImages}
            id={IdUtils.create_id("nodeimagescomponent#{nodename}")}
            node={nodename}
            info={info}
            images={Map.get(@images, nodename, [])}
          />
        </.modal>
      <% end %>
    </Layouts.operational_page>
    """
  end

  def handle_page_broadcast({:images, payload}, socket) do
    {:ok, %{images: images}} = Projections.broadcast_assigns(:images, payload)
    assign_image_data(socket, images)
  end

  def handle_page_broadcast({:cluster_info, payload}, socket) do
    {:ok, %{cluster_info: cluster_info}} = Projections.broadcast_assigns(:cluster_info, payload)

    assign(socket,
      cluster_info: cluster_info,
      image_node_rows: Presentation.node_rows(cluster_info)
    )
  end

  def handle_page_broadcast(_message, _socket), do: :unhandled

  defp assign_image_data(socket, images) when is_map(images) do
    images_list = Image.flatten_node_map(images)

    assign(socket,
      images: images,
      images_list: images_list,
      image_presentation: Presentation.build(images_list)
    )
  end
end
