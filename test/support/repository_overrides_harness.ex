defmodule ExdockWeb.HomepageLiveTest.RepositoryOverridesHarness do
  @moduledoc false

  use ExdockWeb, :live_view

  alias Exdock.Domain.Image.Metadata

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     Phoenix.Component.assign(socket,
       repository_overrides: %{
         "alpine:latest" => %Metadata{repository_url: "https://github.com/alpine"}
       }
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={ExdockWeb.PageLive.RepositoryOverridesManager}
      id="repository-overrides-manager"
      modal_id="repository-overrides"
      repository_overrides={@repository_overrides}
    />
    """
  end
end
