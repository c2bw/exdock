defmodule ExdockWeb.Commons.NodeSummary.HardwareUsage do
  @moduledoc "Current aggregate container resource usage for a node."

  use ExdockWeb, :html

  attr :id, :string, required: true
  attr :platform, :string, default: nil
  attr :rows, :list, required: true

  def render(assigns) do
    assigns = assign(assigns, :metrics, List.flatten(assigns.rows))

    ~H"""
    <section
      id={@id}
      class="mt-1.5 overflow-hidden rounded-lg border border-tertiary bg-primary-lighter shadow-sm"
      aria-labelledby={"#{@id}-title"}
    >
      <div class="flex items-center justify-between border-b border-tertiary px-3 py-2">
        <div class="flex min-w-0 items-center gap-2.5">
          <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-md border border-tertiary bg-secondary text-mid-visibility">
            <.icon name="hero-chart-bar-square" class="h-4 w-4" />
          </span>
          <div class="min-w-0">
            <h2 id={"#{@id}-title"} class="truncate text-xs font-semibold text-high-visibility">
              Hardware Usage
            </h2>
            <p class="truncate text-[0.65rem] leading-4 text-low-visibility">
              Aggregate usage across this node's containers
            </p>
          </div>
        </div>

        <div class="ms-3 flex shrink-0 items-center gap-1.5">
          <span
            :if={@platform}
            id={"#{@id}-platform"}
            class="inline-flex items-center gap-1 rounded-full border border-tertiary bg-secondary px-2 py-0.5 font-mono text-[0.6rem] font-semibold text-mid-visibility"
          >
            <.icon name="hero-computer-desktop" class="h-3 w-3" />
            {@platform}
          </span>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-px bg-tertiary sm:grid-cols-4">
        <.metric :for={metric <- @metrics} metric={metric} />
      </div>
    </section>
    """
  end

  attr :metric, :map, required: true

  defp metric(assigns) do
    ~H"""
    <div class="group bg-primary-lighter px-3 py-2.5 transition-colors duration-150 hover:bg-secondary">
      <div class="mb-1.5 flex items-center justify-between">
        <span class="text-[0.6rem] font-semibold uppercase tracking-[0.12em] text-low-visibility">
          {@metric.label}
        </span>
        <.icon
          name={@metric.icon}
          class="h-3.5 w-3.5 text-low-visibility transition-colors duration-150 group-hover:text-mid-visibility"
        />
      </div>
      <p class="font-mono text-base font-semibold leading-5 tracking-tight text-high-visibility">
        {@metric.value}
      </p>
      <p class="mt-0.5 truncate font-mono text-[0.625rem] leading-4 text-low-visibility">
        {@metric.detail}
      </p>
    </div>
    """
  end
end
