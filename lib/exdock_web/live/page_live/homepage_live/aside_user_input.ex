defmodule ExdockWeb.HomepageLive.AsideUserInput do
  use ExdockWeb, :html
  alias ExdockWeb.PageLive.Utils.ModalState

  attr :id, :string, required: true
  attr :modals_to_render, :map, required: true
  attr :active_modal_id, :string, default: nil
  attr :containers, :map, required: true
  attr :containers_revision, :integer, required: true
  attr :containers_extended, :map, required: true
  attr :repositories, :any, required: true
  attr :clock_now, :any, required: true

  def render(assigns) do
    ~H"""
    <div class="mt-4 flex flex-col space-y-4">
      <div class="w-full place-self-center space-y-2">
        <ExdockWeb.Components.Sidebar.action
          id="homepage-registry-fetch-button"
          click="registry_fetch"
          text="fetch registry"
          hint="Sync available images"
          icon="hero-bars-arrow-down"
        />
        <ExdockWeb.Components.Sidebar.action
          id="homepage-node-refresh-button"
          click="node_refresh_cluster"
          text="refresh nodes"
          hint="Update cluster state"
          icon="hero-arrow-path"
        />
        <div class="pt-0.5 text-center">
          <div>
            <ExdockWeb.Components.Sidebar.secondary_action
              id="homepage-mass-manager-button"
              click={show_lazy_modal("mass-container-manager")}
              text="Mass Manager"
              icon="hero-chevron-up-down"
            />
            <.modal id="mass-container-manager" max_width="max-w-3xl">
              <div :if={ModalState.render?(@modals_to_render, "mass-container-manager")}>
                <.live_component
                  module={ExdockWeb.HomepageLive.MassContainerManager}
                  id="mass-container-manager-component"
                  modals_to_render={@modals_to_render}
                  active_modal_id={assigns[:active_modal_id]}
                  containers={@containers}
                  containers_revision={@containers_revision}
                  containers_extended={@containers_extended}
                  repositories={@repositories}
                  clock_now={@clock_now}
                />
              </div>
            </.modal>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
