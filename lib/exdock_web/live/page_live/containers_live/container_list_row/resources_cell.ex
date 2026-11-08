defmodule ExdockWeb.ContainersLive.ContainerListRow.ResourcesCell do
  @moduledoc false

  use ExdockWeb, :html

  attr :metrics, :list, required: true

  def render(assigns) do
    ~H"""
    <div :if={@metrics != []} class="container-resource-metrics">
      <div
        :for={metric <- @metrics}
        class="container-resource-metric"
        title={"#{metric.label}: #{metric.value}"}
      >
        <span class="truncate">{metric.value}</span>
        <.icon name={metric.icon} class="size-3.5 shrink-0 text-low-visibility" />
        <span class="sr-only">{metric.label}</span>
      </div>
    </div>
    """
  end
end
