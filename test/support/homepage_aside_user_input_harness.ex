defmodule ExdockWeb.HomepageLiveTest.AsideUserInputHarness do
  @moduledoc false

  use ExdockWeb, :live_view

  alias Exdock.ReadModel.Container
  alias Exdock.ReadModel.Container.Key
  alias Exdock.Domain.Container, as: StorageContainer
  alias Exdock.Domain.Container.Extended
  alias ExdockWeb.HomepageLiveTest.MassManagerHarness

  @impl true
  def mount(_params, _session, socket) do
    container =
      %StorageContainer{
        node: "mass_node",
        name: "api",
        id: "api-id",
        core: MassManagerHarness.core_fixture(),
        extended: Extended.new()
      }
      |> Container.from_domain()

    {:ok,
     Phoenix.Component.assign(socket,
       containers: %{"mass_node" => [container]},
       containers_revision: 1,
       containers_extended: %{"mass_node" => %{Key.new("api", "api-id") => container.extended}},
       modals_to_render: %{"mass-container-manager" => true},
       active_modal_id: nil,
       repositories: [],
       clock_now: ~U[2026-06-01 10:05:00Z]
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ExdockWeb.HomepageLive.AsideUserInput.render
      id="aside-user-input"
      containers={@containers}
      containers_revision={@containers_revision}
      containers_extended={@containers_extended}
      modals_to_render={@modals_to_render}
      active_modal_id={@active_modal_id}
      repositories={@repositories}
      clock_now={@clock_now}
    />
    """
  end
end
