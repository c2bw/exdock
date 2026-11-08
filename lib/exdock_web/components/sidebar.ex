defmodule ExdockWeb.Components.Sidebar do
  @moduledoc """
  Shared controls for page sidebars.

  Keeps primary data actions and secondary modal actions visually and
  behaviorally consistent across all LiveView pages.
  """

  use ExdockWeb, :html

  attr :id, :string, required: true
  attr :click, :any, required: true
  attr :text, :string, required: true
  attr :hint, :string, required: true
  attr :icon, :string, required: true

  def action(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click={@click}
      class="control-lift-action sidebar-primary-action group phx-click-loading:opacity-60"
    >
      <span class="control-icon-tile sidebar-action-icon">
        <.icon name={@icon} class="h-4 w-4 transition-transform group-hover:scale-110" />
      </span>

      <span class="min-w-0 flex-1 text-left">
        <span class="block truncate font-mono text-xs font-bold tracking-tight text-high-visibility">{@text}</span>
        <span class="mt-0.5 block truncate font-mono text-xxs text-low-visibility">{@hint}</span>
      </span>

      <span class="sidebar-action-affordance">
        <.icon name="hero-chevron-right" class="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5" />
      </span>
    </button>
    """
  end

  attr :id, :string, required: true
  attr :click, :any, required: true
  attr :text, :string, required: true
  attr :icon, :string, default: "hero-ellipsis-horizontal"

  def secondary_action(assigns) do
    ~H"""
    <button id={@id} type="button" class="sidebar-secondary-action group" phx-click={@click}>
      <span>{@text}</span> <.icon name={@icon} class="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5" />
    </button>
    """
  end
end
