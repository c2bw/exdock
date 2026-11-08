defmodule ExdockWeb.ImagesLive.AsideUserInput do
  use ExdockWeb, :html

  attr :id, :string, required: true
  attr :registries, :list, required: true

  def render(assigns) do
    ~H"""
    <div class="mt-4 flex flex-col space-y-4">
      <div class="w-full place-self-center space-y-2">
        <ExdockWeb.Components.Sidebar.action
          id="images-node-refresh-button"
          click="node_refresh_cluster"
          text="refresh nodes"
          hint="Update cluster state"
          icon="hero-arrow-path"
        />
        <div class="pt-0.5 text-center">
          <div>
            <ExdockWeb.Components.Sidebar.secondary_action
              id="images-registries-button"
              click={show_modal("registries_info")}
              text="registries"
            />
            <.modal id="registries_info">
              <ExdockWeb.ImagesLive.Registries.render id="registries_info-component" registries={@registries} />
            </.modal>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
