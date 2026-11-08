defmodule ExdockWeb.ContainersLiveTest.ContainersListHarness do
  @moduledoc false

  use ExdockWeb, :live_view

  alias Exdock.ReadModel.Container
  alias Exdock.ReadModel.Container.Key
  alias ExdockWeb.TestFixtures.Container, as: ContainerFixture

  @impl true
  def mount(_params, _session, socket) do
    now = ~U[2026-06-01 10:00:00Z]

    containers =
      [
        container("api-unknown", :unknown, true, now),
        container("api-outdated", :outdated, true, now),
        container("api-updated", :updated, true, now),
        container("api-stopped", :updated, false, now)
      ]

    {:ok,
     assign(socket,
       containers: Map.new(containers, fn {key, core} -> {key, core} end),
       containers_extended: Map.new(containers, fn {key, _core} -> {key, Container.empty_extended()} end),
       modals_to_render: %{},
       active_modal_id: nil,
       repositories: [],
       clock_now: now,
       containers_revision: 1,
       last_event: ""
     )}
  end

  @impl true
  def handle_event("show_lazy_modal", %{"modal_id" => modal_id}, socket) do
    {:noreply, Phoenix.Component.assign(socket, :active_modal_id, modal_id)}
  end

  def handle_event(event, params, socket) do
    value =
      case params do
        %{"node" => node, "image_tag" => image_tag} -> "#{node},#{image_tag}"
        _params -> "submit"
      end

    {:noreply, Phoenix.Component.assign(socket, :last_event, "#{event}:#{value}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="containers-list-harness">
      <.live_component
        module={ExdockWeb.ContainersLive.ContainersList}
        id="containers_list_component"
        active_modal_id={@active_modal_id}
        containers={@containers}
        containers_extended={@containers_extended}
        nodename="harness_node"
        repositories={@repositories}
        clock_now={@clock_now}
        containers_revision={@containers_revision}
      />
      <p id="last-containers-list-event">{@last_event}</p>
    </div>
    """
  end

  defp container(name, image_status, running?, now) do
    key = Key.new(name, "#{name}-id")

    core =
      ContainerFixture.read_model(
        name: name,
        image_status: image_status,
        is_running: running?,
        now: now,
        pid: System.unique_integer([:positive])
      ).core

    {key, core}
  end
end
