defmodule ExdockWeb.ContainersLive.ContainersList do
  use ExdockWeb, :live_component
  alias ExdockWeb.ContainersLive.ContainerGroups

  @impl true
  def update(%{containers_revision: revision} = assigns, socket) do
    containers_changed? = socket.assigns[:containers_revision] != revision

    socket =
      if containers_changed? do
        assign(
          socket,
          :groups,
          ContainerGroups.build(assigns.containers, assigns.containers_extended)
        )
      else
        socket
      end

    {:ok, assign(socket, Map.drop(assigns, [:containers, :containers_extended]))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="node-containers-list min-w-full overflow-x-auto">
      <div class="flex max-h-full min-w-max flex-col overflow-x-hidden">
        <.live_component
          module={ExdockWeb.ContainersLive.ContainersTable}
          id={"unkORerr"<> @id}
          active_modal_id={assigns[:active_modal_id]}
          outerdivclass="container-group container-group--unknown grow"
          headlinetext="unknown / errored"
          containers={@groups.unknown}
          nodename={@nodename}
          is_outdated={false}
          is_running={true}
          repositories={@repositories}
          clock_now={@clock_now}
          containers_revision={@containers_revision}
        />
        <.live_component
          module={ExdockWeb.ContainersLive.ContainersTable}
          id={"outdated"<> @id}
          active_modal_id={assigns[:active_modal_id]}
          outerdivclass="container-group container-group--outdated grow"
          headlinetext="outdated"
          containers={@groups.outdated}
          nodename={@nodename}
          is_outdated={true}
          is_running={true}
          repositories={@repositories}
          clock_now={@clock_now}
          containers_revision={@containers_revision}
        />
        <.live_component
          module={ExdockWeb.ContainersLive.ContainersTable}
          id={"ok"<> @id}
          active_modal_id={assigns[:active_modal_id]}
          outerdivclass="container-group container-group--updated grow"
          headlinetext="ok"
          containers={@groups.ok}
          nodename={@nodename}
          is_outdated={false}
          is_running={true}
          repositories={@repositories}
          clock_now={@clock_now}
          containers_revision={@containers_revision}
        />
        <.live_component
          module={ExdockWeb.ContainersLive.ContainersTable}
          id={"not_running"<> @id}
          active_modal_id={assigns[:active_modal_id]}
          outerdivclass="container-group container-group--stopped grow"
          headlinetext="not running"
          containers={@groups.stopped}
          nodename={@nodename}
          is_outdated={false}
          is_running={false}
          repositories={@repositories}
          clock_now={@clock_now}
          containers_revision={@containers_revision}
        />
      </div>
    </div>
    """
  end
end
