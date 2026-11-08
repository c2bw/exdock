defmodule ExdockWeb.PageLive.AsideNodeInfo do
  use ExdockWeb, :html
  alias ExdockWeb.PageLive.Utils.URLParam

  attr :id, :string, required: true
  attr :nodes_list, :list, required: true
  attr :nodes_count, :integer, required: true

  def render(assigns) do
    ~H"""
    <section class="flex flex-col gap-2" aria-labelledby="sidebar-nodes-title">
      <div class="flex items-center justify-between px-0.5">
        <div class="flex min-w-0 items-center gap-2">
          <span class="control-icon-tile sidebar-icon-tile sidebar-icon-tile--compact">
            <.icon name="hero-server-stack" class="size-3.5" />
          </span>

          <div class="min-w-0">
            <p
              id="sidebar-nodes-title"
              class="font-mono text-xs font-bold leading-tight tracking-tight text-high-visibility"
            >
              Nodes
            </p>

            <p class="font-mono text-xxs uppercase leading-tight tracking-[0.14em] text-low-visibility">
              Cluster
            </p>
          </div>
        </div>
        <span
          class="sidebar-count sidebar-count--compact"
          aria-label={"#{@nodes_count} connected nodes"}
        >
          {@nodes_count}
        </span>
      </div>

      <div class="sidebar-card max-h-40 overflow-y-auto p-1">
        <ul class="w-full space-y-0.5 font-mono text-xs font-semibold">
          <%= if @nodes_count > 0 do %>
            <%= for node <- @nodes_list do %>
              <li>
                <.link
                  navigate={~p"/containers/#{URLParam.encode(node)}"}
                  class="sidebar-node-link sidebar-node-link--compact group"
                >
                  <span class="h-1 w-1 shrink-0 rounded-full bg-container-updated ring-2 ring-[var(--surface-raised)]"></span>
                  <span class="min-w-0 flex-1 truncate">{node}</span>
                  <.icon
                    name="hero-chevron-right"
                    class="h-3 w-3 shrink-0 opacity-0 transition-all group-hover:translate-x-0.5 group-hover:opacity-100"
                  />
                </.link>
              </li>
            <% end %>
          <% else %>
            <li class="flex min-h-8 items-center justify-center gap-1.5 px-2 text-xs font-medium text-low-visibility">
              <span class="h-1.5 w-1.5 rounded-full bg-[var(--line-strong)]"></span> No nodes connected
            </li>
          <% end %>
        </ul>
      </div>
    </section>
    """
  end
end
