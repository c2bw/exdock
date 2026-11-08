defmodule ExdockWeb.ContainersLive.ContainerListRow.BuildCell do
  @moduledoc false

  use ExdockWeb, :html

  attr :build, :map, required: true

  def render(assigns) do
    ~H"""
    <%= case @build.mode do %>
      <% :comparison -> %>
        <p class="container-build-comparison">
          <span class="text-xxs tracking-tighter">local</span><span class="text-xxs font-semibold tracking-tighter text-mid-visibility">[{@build.local}]</span>
          <%= if @build.remote do %>
            <span class="text-xxs tracking-tighter">remote</span><span class="text-xxs font-semibold tracking-tighter text-mid-visibility">[{@build.remote}]</span>
            → <span class="font-semibold tracking-tighter text-high-visibility">{@build.age_days}</span>
            <span class="text-xxs tracking-tighter">days</span>
          <% end %>
        </p>
      <% :current -> %>
        <p class="container-build-date">
          <span class="text-xs font-semibold tracking-tighter text-high-visibility">
            {@build.local}
          </span>
        </p>
    <% end %>
    """
  end
end
