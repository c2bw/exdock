defmodule ExdockWeb.ContainersLive.ContainerListRow.StateCell do
  @moduledoc false

  use ExdockWeb, :html

  attr :lifecycle, :map, default: nil
  attr :network, :atom, default: nil

  def render(assigns) do
    ~H"""
    <span :if={@lifecycle} title={@lifecycle.title}>
      <.icon name="hero-cog" class={["size-4 shrink-0", @lifecycle.color]} />
    </span>
    <span :if={@network == :host} title="Host network">
      <.icon name="hero-globe-alt" class="size-4 shrink-0 text-high-visibility" />
    </span>
    <span :if={@network == :published} title="Published ports">
      <.icon name="hero-globe-alt" class="size-4 shrink-0 text-low-visibility" />
    </span>
    """
  end
end
