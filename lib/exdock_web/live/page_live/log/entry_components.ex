defmodule ExdockWeb.PageLive.Log.EntryComponents do
  @moduledoc "Shared visual primitives for compact and detailed log entries."

  use ExdockWeb, :html

  alias ExdockWeb.PageLive.Log

  attr :status, :map, default: nil

  def status_icon(assigns) do
    ~H"""
    <%= if @status do %>
      <span class={@status.text_color}>
        <.icon name={@status.icon} class="mb-0.5 mr-0 h-3 w-3 lg:h-4 lg:w-4" />
      </span>
    <% end %>
    """
  end

  attr :count, :integer, required: true

  def release_count(assigns) do
    ~H"""
    <%= if @count > 0 do %>
      <span class="tracking-tighter text-low-visibility">
        <.icon name="hero-plus" class="mb-0 mr-0 h-3 w-3 text-mid-visibility" />{@count}
      </span>
    <% end %>
    """
  end

  attr :counts, :map, required: true

  def refresh_counts(assigns) do
    assigns =
      assign(assigns, :items, [
        {assigns.counts.new, "text-green-800", "hero-plus"},
        {assigns.counts.vanished, "text-yellow-800", "hero-minus"},
        {assigns.counts.started, "text-lime-700", "hero-arrow-long-up"},
        {assigns.counts.stopped, "text-amber-700", "hero-arrow-long-down"},
        {assigns.counts.errored, "text-error", "hero-exclamation-triangle"}
      ])

    ~H"""
    <span class="tracking-tighter">
      <%= for {count, color, icon} <- @items, count > 0 do %>
        <span class={color}><.icon name={icon} class="mb-0 mr-0 h-3 w-3" />{count}</span>
      <% end %>
    </span>
    """
  end

  attr :old_status, :any, required: true
  attr :new_status, :any, required: true

  def container_transition(assigns) do
    assigns =
      assign(assigns,
        old_color: Log.container_status_to_text_color(assigns.old_status),
        old_icon: Log.container_status_to_icon_name(assigns.old_status),
        new_color: Log.container_status_to_text_color(assigns.new_status),
        new_icon: Log.container_status_to_icon_name(assigns.new_status)
      )

    ~H"""
    <span class={@old_color}>
      <.icon name={@old_icon} class="mb-1 mr-0 h-3 w-3 lg:h-4 lg:w-4" />
    </span>
    <span>→</span>
    <span class={@new_color}>
      <.icon name={@new_icon} class="mb-1 mr-0 h-3 w-3 lg:h-4 lg:w-4" />
    </span>
    """
  end
end
