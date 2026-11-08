defmodule ExdockWeb.Commons.NodeSummary.Status do
  @moduledoc "Stateless node health, update status, and staleness presentation."

  use ExdockWeb, :html

  attr :model, :map, required: true

  def render(assigns) do
    ~H"""
    <.status_summary status={@model.status} />
    <.state_icons :if={@model.summary_type == :containers} icons={@model.state_icons} />
    <.staleness staleness={@model.staleness} />
    """
  end

  attr :status, :map, required: true

  defp status_summary(assigns) do
    ~H"""
    <div class="ms-1 flex w-48 shrink-0 max-2xl:w-48 max-xl:w-44 max-lg:w-32 max-[864px]:hidden">
      <div class="flex gap-x-1">
        <%= if @status.visible? do %>
          <.status_bars items={@status.items} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :items, :list, required: true

  defp status_bars(assigns) do
    ~H"""
    <div class="ms-1 w-0 truncate py-3 font-mono">&nbsp;</div>
    <div class="flex-row">
      <div class="flex h-full flex-row flex-wrap gap-x-px py-3">
        <.status_bar :for={item <- @items} item={item} />
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  defp status_bar(assigns) do
    ~H"""
    <div
      :for={_bar <- List.duplicate(:bar, @item.count)}
      class={["flex w-[4px] rounded", @item.bar_color]}
      title={@item.label}
      aria-label={@item.label}
    />
    """
  end

  attr :icons, :map, required: true

  defp state_icons(assigns) do
    ~H"""
    <div class="flex w-16 shrink-0 justify-end">
      <div class="flex flex-row flex-nowrap items-end justify-end gap-x-0.5 truncate font-mono">
        <.state_icon icon={@icons.restarting} />
        <.state_icon icon={@icons.recently_started} />
      </div>
    </div>
    """
  end

  attr :icon, :map, default: nil

  defp state_icon(assigns) do
    ~H"""
    <div class="flex min-w-6">
      <.icon :if={@icon} name={@icon.icon} class={["mb-1 h-5 w-5", @icon.color]} />
    </div>
    """
  end

  attr :staleness, :map, required: true

  defp staleness(assigns) do
    ~H"""
    <div class="flex w-44 shrink-0 justify-start max-2xl:w-32 max-xl:w-12">
      <div class="flex flex-row flex-nowrap items-center justify-start gap-x-0.5 truncate font-mono">
        <div class="flex min-w-6">
          <.icon
            :if={@staleness.icon}
            name={@staleness.icon}
            class={["mb-1 h-5 w-5", @staleness.color]}
          />
        </div>

        <div class="flex min-w-6 w-full">
          <p :if={@staleness.text} class="mb-1.5 truncate font-mono">
            <span class="me-1 text-xs tracking-tighter text-low-visibility max-xl:hidden">
              <span class="max-2xl:hidden">Updated: </span>{@staleness.text}
            </span>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
