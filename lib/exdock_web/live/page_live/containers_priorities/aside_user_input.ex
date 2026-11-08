defmodule ExdockWeb.ContainersPriorities.AsideUserInput do
  use ExdockWeb, :html

  def render(assigns) do
    ~H"""
    <div class="mt-4 flex flex-col space-y-4">
      <div class="w-full place-self-center space-y-2">
        <ExdockWeb.Components.Sidebar.action
          id="priorities-registry-fetch-button"
          click="registry_fetch"
          text="fetch registry"
          hint="Sync available images"
          icon="hero-bars-arrow-down"
        />
        <ExdockWeb.Components.Sidebar.action
          id="priorities-node-refresh-button"
          click="node_refresh_cluster"
          text="refresh nodes"
          hint="Update cluster state"
          icon="hero-arrow-path"
        />
      </div>
    </div>
    """
  end
end
