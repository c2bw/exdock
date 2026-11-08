defmodule ExdockWeb.ContainersPriorities.Index do
  @moduledoc """
  LiveView for reviewing and editing container update priorities.

  The page is a focused editor over the same container settings used by
  automation, with imports routed through the shared page handler.
  """

  use ExdockWeb, :live_view

  use ExdockWeb.PageLive.LivePage.Use,
    title: "Priorities",
    load: [:nodes, :containers],
    clock: false

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.operational_page
      id="containers-priorities-index"
      content_width={:wide}
      context={ExdockWeb.PageLive.LivePage.shell_context(assigns)}
    >
      <:aside>
        <ExdockWeb.ContainersPriorities.AsideUserInput.render id="aside-user-input" />
        <div class="flex flex-grow items-end"></div>
        <ExdockWeb.PageLive.Log.render id="aside-container-log" modals_to_render={@modals_to_render} log={@log} />
      </:aside>

      <div class="w-full">
        <.live_component
          module={ExdockWeb.ContainersPriorities.Containers}
          id="priorities-containers"
          containers={@containers}
        />
      </div>
    </Layouts.operational_page>
    """
  end
end
