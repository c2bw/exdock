defmodule ExdockWeb.PageLive.AsideComponent do
  @moduledoc """
  Shared sidebar shell used by the main LiveView pages.

  Page-specific controls are passed through slots/components while this module
  owns the consistent node list, render-statistics display, and sidebar layout.
  """

  use ExdockWeb, :html

  attr :nodes_list, :list, required: true
  attr :show_render_stats?, :boolean, required: true
  attr :client_latency, :any, required: true
  attr :js_render_time, :any, required: true
  attr :server_render_time, :any, required: true

  slot :inner_content

  def render(assigns) do
    ~H"""
    <aside
      id="left-sidebar"
      class="sidebar-shell flex min-w-fit w-56 flex-col justify-start overflow-x-hidden overflow-y-auto border-r border-primary px-3 pb-3 pt-5 lg:w-64"
      aria-label="Cluster controls"
    >
      <%!-- Node info --%>
      <ExdockWeb.PageLive.AsideNodeInfo.render
        id="aside-node-info"
        nodes_list={@nodes_list}
        nodes_count={@nodes_list |> length()}
      /> <%!-- Page-specific controls --%> {render_slot(@inner_content)} <%!-- Render statistics --%>
      <ExdockWeb.PageLive.RenderStatistics.render
        id="aside-render-statistics"
        show?={@show_render_stats?}
        client_latency={@client_latency}
        js_render_time={@js_render_time}
        server_render_time={@server_render_time}
      /> <%!-- Default footer --%> <ExdockWeb.PageLive.AsideFooter.render id="aside-footer" />
    </aside>
    """
  end
end
