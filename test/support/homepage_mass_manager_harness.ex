defmodule ExdockWeb.HomepageLiveTest.MassManagerHarness do
  @moduledoc false

  use ExdockWeb, :live_view
  alias ExdockWeb.TestFixtures.Container, as: ContainerFixture

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     Phoenix.Component.assign(socket,
       containers: containers(),
       containers_revision: 1,
       modals_to_render: %{},
       active_modal_id: nil,
       clock_now: ~U[2026-06-01 10:05:00Z]
     )}
  end

  @impl true
  def handle_event("show_lazy_modal", %{"modal_id" => modal_id}, socket) do
    {:noreply, Phoenix.Component.assign(socket, :active_modal_id, modal_id)}
  end

  def handle_event(event, params, socket) do
    event_value =
      case params do
        %{"images" => [%{"node" => node, "image_tag" => image_tag}]} ->
          "#{node},#{image_tag}"

        %{
          "containers" => [%{"node" => node, "name" => name}],
          "image_pull" => image_pull
        } ->
          "#{node},#{name}:#{image_pull}"
      end

    {:noreply, Phoenix.Component.assign(socket, :last_event, "#{event}:#{event_value}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="mass-manager-harness">
      <.live_component
        module={ExdockWeb.HomepageLive.MassContainerManager}
        id="mass-container-manager-component"
        modals_to_render={@modals_to_render}
        active_modal_id={@active_modal_id}
        containers={@containers}
        containers_revision={@containers_revision}
        containers_extended={%{}}
        repositories={[]}
        clock_now={@clock_now}
      />
      <p id="last-mass-manager-event">{assigns[:last_event]}</p>
    </div>
    """
  end

  defp containers, do: %{"mass_node" => [container_fixture()]}

  def core_fixture do
    container_fixture().core
  end

  defp container_fixture do
    ContainerFixture.read_model(
      node: "mass_node",
      name: "api",
      image_status: :outdated,
      priority: 4
    )
  end
end
