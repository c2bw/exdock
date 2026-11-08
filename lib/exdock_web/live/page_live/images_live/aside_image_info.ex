defmodule ExdockWeb.ImagesLive.AsideImageInfo do
  use ExdockWeb, :html

  attr :id, :string, required: true
  attr :modals_to_render, :map, required: true
  attr :summary, :map, required: true
  attr :log, :list, required: true

  def render(assigns) do
    ~H"""
    <div class="flex flex-col flex-grow space-y-2 mt-4">
      <div class="flex flex-grow items-end"></div>
      <ExdockWeb.PageLive.Log.render id="aside-images-log" modals_to_render={@modals_to_render} log={@log} />
      <%= if @summary.total > 0 do %>
        <section id="sidebar-images-summary" class="sidebar-card p-2" aria-labelledby="sidebar-images-title">
          <div class="flex items-center justify-between px-1.5 pb-2 pt-1">
            <div class="flex min-w-0 items-center gap-2.5">
              <span class="control-icon-tile sidebar-icon-tile size-8">
                <.icon name="hero-square-2-stack" class="size-4" />
              </span>

              <div class="min-w-0">
                <p id="sidebar-images-title" class="font-mono text-xs font-bold tracking-tight text-high-visibility">
                  Images
                </p>

                <p class="font-mono text-xxs text-low-visibility">Cluster inventory</p>
              </div>
            </div>
            <span class="sidebar-count" aria-label={"#{@summary.total} images total"}>{@summary.total}</span>
          </div>

          <div class="space-y-1">
            <.image_info
              text="Used"
              description="Attached to containers"
              icon="hero-link"
              color="text-container-updated"
              surface="bg-[var(--accent-soft)]"
              count={@summary.used}
            />
            <.image_info
              text="Unused"
              description="Available for cleanup"
              icon="hero-archive-box"
              color="text-container-outdated"
              surface="bg-amber-500/10"
              count={@summary.unused}
            />
            <.image_info
              text="Locked"
              description="Protected from deletion"
              icon="hero-lock-closed"
              color="text-container-unknown"
              surface="bg-slate-500/10"
              count={@summary.locked}
            />
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  defp image_info(assigns) do
    ~H"""
    <div class="group flex min-h-12 items-center gap-2 rounded-lg border border-transparent px-2 py-1.5 transition-colors hover:border-secondary hover:bg-secondary">
      <span class={[
        "grid size-8 shrink-0 place-items-center rounded-lg border border-secondary transition-colors group-hover:border-[var(--line-default)]",
        @color,
        @surface
      ]}>
        <.icon name={@icon} class="size-4" />
      </span>

      <div class="min-w-0 flex-1">
        <p class="truncate font-mono text-xs font-semibold text-high-visibility">{@text}</p>

        <p class="truncate font-mono text-[0.625rem] text-low-visibility">{@description}</p>
      </div>

      <span
        class={[
          "min-w-7 rounded-md border border-secondary bg-primary px-1.5 py-1 text-center font-mono text-xs font-bold tabular-nums",
          @color
        ]}
        aria-label={"#{@count} #{@text} images"}
      >
        {@count}
      </span>
    </div>
    """
  end
end
