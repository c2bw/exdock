defmodule ExdockWeb.Commons.NodeSummary.Overview do
  @moduledoc "Stateless node identity, inventory, and resource presentation."

  use ExdockWeb, :html

  attr :model, :map, required: true

  def render(assigns) do
    ~H"""
    <.nodename nodename={@model.nodename} />
    <.metrics metrics={@model.metrics} />
    <.resources :if={@model.resource_rows != []} rows={@model.resource_rows} />
    """
  end

  attr :nodename, :string, required: true

  defp nodename(assigns) do
    ~H"""
    <div class="flex w-44 shrink-0 justify-start max-xl:w-40 max-lg:w-36 max-md:w-32" title={@nodename}>
      <div class="flex min-w-0 items-center gap-2.5 py-2.5 pe-2 ps-4">
        <span
          aria-hidden="true"
          class={[
            "grid h-8 w-8 shrink-0 place-items-center rounded-lg border border-secondary bg-primary text-eye shadow-sm",
            "transition-all duration-200 group-hover:border-[var(--accent)] group-hover:bg-primary-lighter group-hover:text-[var(--accent-bright)]"
          ]}
        >
          <.icon name="hero-server-stack" class="h-4 w-4" />
        </span>

        <div class="min-w-0">
          <span class="block text-[0.6rem] font-semibold uppercase leading-3 tracking-[0.14em] text-low-visibility">
            Node
          </span>
          <p class="truncate font-mono text-sm font-bold leading-5 tracking-tight text-high-visibility">
            {@nodename}
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :metrics, :list, required: true

  defp metrics(assigns) do
    ~H"""
    <div class="me-3 mt-0 flex w-36 shrink-0 max-2xl:hidden">
      <div class="flex flex-row gap-x-0.5">
        <.metric :for={metric <- @metrics} metric={metric} />
      </div>
    </div>
    """
  end

  attr :metric, :map, required: true

  defp metric(assigns) do
    ~H"""
    <div
      class={[
        "flex min-w-10 flex-col items-center justify-center rounded-lg border border-transparent px-0.5 py-1",
        "transition-colors duration-200 group-hover:border-secondary group-hover:bg-primary-lighter"
      ]}
      title={@metric.label}
    >
      <p class="m-0 text-nowrap text-xsm tracking-tighter text-mid-visibility">
        <.icon
          name={@metric.icon}
          class="h-4 w-4 text-low-visibility transition-colors duration-200 group-hover:text-eye"
        />
        <span class="font-mono font-semibold text-high-visibility">{@metric.value}</span>
      </p>
      <span class="text-[0.6rem] uppercase leading-none tracking-wide text-low-visibility">
        {@metric.label}
      </span>
    </div>
    """
  end

  attr :rows, :list, required: true

  defp resources(assigns) do
    ~H"""
    <div class="mt-0.5 flex w-52 shrink-0 flex-col max-xl:hidden">
      <div :for={row <- @rows} class="flex w-52 flex-row flex-nowrap gap-x-2">
        <.resource :for={resource <- row} resource={resource} />
      </div>
    </div>
    """
  end

  attr :resource, :map, required: true

  defp resource(assigns) do
    ~H"""
    <div class="flex w-1/2">
      <p class="text-nowrap text-xs font-semibold tracking-tighter text-mid-visibility" title={@resource.label}>
        <.icon name={@resource.icon} class="mb-0.5 h-5 w-5 text-mid-visibility" />
        <span class="me-1 text-[0.6rem] uppercase tracking-wide text-low-visibility">
          {@resource.label}
        </span>
        <span class="font-mono">{@resource.value}</span>
      </p>
    </div>
    """
  end
end
