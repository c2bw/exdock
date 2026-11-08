defmodule ExdockWeb.PageLive.RenderStatistics do
  @moduledoc """
  Small UI component for displaying LiveView render and browser timing metrics.

  Measurements are gathered by the shared page handler and browser hook, then
  rendered here when the user setting enables diagnostics.
  """

  use ExdockWeb, :html

  attr :id, :string, required: true
  attr :show?, :boolean, required: true
  attr :client_latency, :any, required: true
  attr :js_render_time, :any, required: true
  attr :server_render_time, :any, required: true

  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
      <div :if={@show?} class="sidebar-card mt-2 flex px-2 py-2.5">
        <.metrics client_latency={@client_latency} js_render_time={@js_render_time} server_render_time={@server_render_time} />
      </div>
    </div>
    """
  end

  defp metrics(assigns) do
    ~H"""
    <div class="w-full justify-stretch">
      <div class="mb-1.5 flex items-center gap-2 px-1">
        <.icon name="hero-bolt" class="h-3.5 w-3.5 text-eye" />
        <p class="font-mono text-xs font-semibold text-mid-visibility">Render stats</p>
      </div>

      <table class="m-0 w-full table-auto rounded font-mono">
        <tbody class="text-left font-mono text-xs text-low-visibility">
          <.line name="Latency" value={@client_latency} /> <.line name="JS Render" value={@js_render_time} />
          <.line name="Phoenix Render" value={@server_render_time} />
        </tbody>
      </table>
    </div>
    """
  end

  defp line(assigns) do
    ~H"""
    <tr class="border-t border-secondary first:border-t-0">
      <td class="py-1.5 ps-1 pe-1">{@name}</td>

      <td class="py-1.5 ps-1 pe-1">
        <p class="min-w-12 w-full text-end font-semibold tabular-nums text-mid-visibility">{@value || "–"}ms</p>
      </td>
    </tr>
    """
  end
end
