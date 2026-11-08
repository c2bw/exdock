defmodule ExdockWeb.HomepageLive.AsideContainerInfo do
  use ExdockWeb, :html

  attr :id, :string, required: true
  attr :modals_to_render, :map, required: true
  attr :log, :list, required: true
  attr :info, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="flex flex-col flex-grow space-y-2 mt-4">
      <div class="flex flex-grow items-end"></div>
      <ExdockWeb.PageLive.Log.render id="aside-container-log" modals_to_render={@modals_to_render} log={@log} />
      <%= if @info.containers.combined.containers_count > 0 do %>
        <section
          id="sidebar-image-status-summary"
          class="sidebar-card p-1.5"
          aria-labelledby="sidebar-image-status-title"
        >
          <div class="flex items-center justify-between gap-2 px-1 pb-1.5 pt-0.5">
            <p
              id="sidebar-image-status-title"
              class="truncate font-mono text-xs font-bold tracking-tight text-high-visibility"
            >
              Image status
            </p>

            <span class="shrink-0 rounded-full border border-secondary px-1.5 py-0.5 font-mono text-[0.625rem] leading-none text-low-visibility">
              {@info.containers.running.containers_count} active
            </span>
          </div>

          <div class="space-y-0.5">
            <.container_status
              name="Errored"
              icon="hero-exclamation-triangle"
              icon_color="text-container-errored"
              bar_color="bg-red-500/70"
              count={@info.containers.running.counters.status.errored.count}
              percentage={@info.containers.running.counters.status.errored.percentage}
            />
            <.container_status
              name="Unknown"
              icon="hero-question-mark-circle"
              icon_color="text-container-unknown"
              bar_color="bg-slate-400/60"
              count={@info.containers.running.counters.status.unknown.count}
              percentage={@info.containers.running.counters.status.unknown.percentage}
            />
            <.container_status
              name="Outdated"
              icon="hero-arrow-down-on-square"
              icon_color="text-container-outdated"
              bar_color="bg-amber-500/75"
              count={@info.containers.running.counters.status.outdated.count}
              percentage={@info.containers.running.counters.status.outdated.percentage}
            />
            <.container_status
              name="Updated"
              icon="hero-check-circle"
              icon_color="text-container-updated"
              bar_color="bg-[var(--accent)]/75"
              count={@info.containers.running.counters.status.updated.count}
              percentage={@info.containers.running.counters.status.updated.percentage}
            />
          </div>
        </section>
      <% end %>

      <section
        id="sidebar-resource-summary"
        class="sidebar-card p-1.5"
        aria-labelledby="sidebar-resource-title"
      >
        <div class="flex items-center justify-between gap-2 px-1 pb-1.5 pt-0.5">
          <p
            id="sidebar-resource-title"
            class="truncate font-mono text-xs font-bold tracking-tight text-high-visibility"
          >
            Resources
          </p>

          <span class="shrink-0 rounded-full border border-secondary px-1.5 py-0.5 font-mono text-[0.625rem] leading-none text-low-visibility">
            active / total
          </span>
        </div>

        <dl class="space-y-0">
          <.statistic
            name="Stacks"
            icon="hero-square-3-stack-3d"
            running_count={@info.containers.running.stacks_count}
            combined_count={@info.containers.combined.stacks_count}
          />
          <.statistic
            name="Containers"
            icon="hero-cube"
            running_count={@info.containers.running.containers_count}
            combined_count={@info.containers.combined.containers_count}
          />
          <.statistic
            name="Images"
            icon="hero-square-2-stack"
            running_count={@info.images.in_use.images_count}
            combined_count={@info.images.combined.images_count}
          />
        </dl>
      </section>
    </div>
    """
  end

  defp container_status(assigns) do
    ~H"""
    <%= if @count > 0 do %>
      <div class="rounded-md border border-transparent px-1.5 py-1 transition-colors hover:border-secondary hover:bg-secondary">
        <div class="flex items-center gap-1.5">
          <span class={[
            "grid size-6 shrink-0 place-items-center rounded-md border border-secondary bg-primary",
            @icon_color
          ]}>
            <.icon name={@icon} class="size-3" />
          </span>
          <span class="min-w-0 flex-1 font-mono text-xs font-semibold text-mid-visibility">{@name}</span>
          <span class="rounded border border-secondary bg-primary px-1 py-0.5 font-mono text-[0.625rem] font-bold leading-none tabular-nums text-high-visibility">
            {@count}
          </span>

          <span class="w-7 text-right font-mono text-[0.625rem] font-semibold tabular-nums text-low-visibility">
            {@percentage}%
          </span>
        </div>

        <div
          class="mt-1 h-0.5 overflow-hidden rounded-full bg-[var(--line-subtle)]"
          role="progressbar"
          aria-label={"#{@name}: #{@percentage}%"}
          aria-valuenow={@percentage}
          aria-valuemin="0"
          aria-valuemax="100"
        >
          <span class={["block h-full rounded-full", @bar_color]} style={"width: #{@percentage}%"} />
        </div>
      </div>
    <% end %>
    """
  end

  defp statistic(assigns) do
    ~H"""
    <div class="sidebar-resource-row group">
      <span class="control-icon-tile sidebar-resource-icon">
        <.icon name={@icon} class="size-3.5 transition-transform group-hover:scale-110" />
      </span>

      <dt class="min-w-0 flex-1 truncate font-mono text-xs font-semibold text-mid-visibility">{@name}</dt>

      <dd
        class="flex items-baseline gap-1 font-mono text-xs tabular-nums"
        aria-label={"#{@running_count} active out of #{@combined_count} total"}
      >
        <span class="font-bold text-eye">{@running_count}</span> <span class="text-low-visibility">/</span>
        <span class="font-semibold text-high-visibility">{@combined_count}</span>
      </dd>
    </div>
    """
  end
end
