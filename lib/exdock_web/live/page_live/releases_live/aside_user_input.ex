defmodule ExdockWeb.ReleasesLive.AsideUserInput do
  use ExdockWeb, :html

  def render(assigns) do
    ~H"""
    <div class="mt-4 flex flex-col space-y-4">
      <div class="w-full place-self-center space-y-2">
        <ExdockWeb.Components.Sidebar.action
          id="releases-fetch-button"
          click="releases_fetch_all"
          text="fetch releases"
          hint="Sync repository releases"
          icon="hero-arrow-down"
        />
      </div>
    </div>
    """
  end
end
