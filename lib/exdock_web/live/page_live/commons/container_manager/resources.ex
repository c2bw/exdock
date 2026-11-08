defmodule ExdockWeb.Commons.ContainerManager.Resources do
  use Phoenix.Component
  import ExdockWeb.CoreComponents
  alias Exdock.Size
  alias ExdockWeb.Format
  alias Exdock.ReadModel.Container

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :detail, :string, required: true
  attr :icon, :string, required: true

  defp metric(assigns) do
    ~H"""
    <div class="rounded-lg border border-secondary bg-primary-lighter p-3 transition-colors hover:border-primary">
      <div class="flex items-start justify-between gap-2">
        <div class="min-w-0">
          <p class="text-[0.625rem] font-semibold uppercase tracking-wider text-low-visibility">{@label}</p>

          <p class="mt-1 truncate font-mono text-sm font-semibold text-high-visibility">{@value}</p>

          <p class="mt-0.5 truncate font-mono text-[0.625rem] text-low-visibility">{@detail}</p>
        </div>

        <span class="grid h-7 w-7 shrink-0 place-items-center rounded-md bg-secondary text-mid-visibility">
          <.icon name={@icon} class="h-4 w-4" />
        </span>
      </div>
    </div>
    """
  end

  attr :core, :map, required: true
  attr :extended, :map, required: true

  def render(assigns) do
    resources = Map.get(assigns.extended || %{}, :resources) || Container.empty_resources()
    totals = latest_resource_totals(resources)

    used_percentage =
      if totals && resources.rates.used_memory && totals.available_memory do
        resources.rates.used_memory / totals.available_memory * 100
      end

    assigns =
      assigns
      |> assign(:resources, resources)
      |> assign(:totals, totals)
      |> assign(:used_percentage, used_percentage)

    ~H"""
    <%= if @core.is_running and @totals do %>
      <div class="grid grid-cols-2 gap-2">
        <.metric
          label="CPU"
          value={Format.percentage(@resources.rates.cpu_usage, 2)}
          detail={"#{@totals.cpu_count || "?"} CPUs"}
          icon="hero-cpu-chip"
        />
        <.metric
          label="Memory"
          value={Size.human_readable(@resources.rates.used_memory)}
          detail={"#{Format.percentage(@used_percentage, 1)} of #{Size.human_readable(@totals.available_memory)}"}
          icon="hero-chart-bar-square"
        />
        <.metric
          label="Disk read"
          value={Size.human_readable(@resources.rates.io.read, time_unit: "/s")}
          detail={"#{Size.human_readable(@totals.io.read)} total"}
          icon="hero-arrow-up-on-square-stack"
        />
        <.metric
          label="Disk write"
          value={Size.human_readable(@resources.rates.io.write, time_unit: "/s")}
          detail={"#{Size.human_readable(@totals.io.write)} total"}
          icon="hero-arrow-down-on-square-stack"
        />
        <.metric
          label="Network up"
          value={Size.human_readable(@resources.rates.net.tx, time_unit: "/s")}
          detail={"#{Size.human_readable(@totals.net.tx)} total"}
          icon="hero-arrow-up"
        />
        <.metric
          label="Network down"
          value={Size.human_readable(@resources.rates.net.rx, time_unit: "/s")}
          detail={"#{Size.human_readable(@totals.net.rx)} total"}
          icon="hero-arrow-down"
        />
      </div>
    <% else %>
      <div class="flex min-h-28 flex-col items-center justify-center rounded-lg border border-dashed border-primary bg-primary-lighter p-4 text-center">
        <.icon name="hero-chart-bar" class="h-5 w-5 text-low-visibility" />
        <p class="mt-2 text-xs font-medium text-mid-visibility">No live metrics</p>

        <p class="mt-0.5 text-[0.675rem] text-low-visibility">
          {if(@core.is_running, do: "Waiting for the next sample", else: "Start the container to collect usage")}
        </p>
      </div>
    <% end %>
    """
  end

  defp latest_resource_totals(resources), do: Container.latest_resources(resources)
end
