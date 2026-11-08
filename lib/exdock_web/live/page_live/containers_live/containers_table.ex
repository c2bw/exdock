defmodule ExdockWeb.ContainersLive.ContainersTable do
  use ExdockWeb, :live_component
  alias ExdockWeb.PageLive.Utils.IdUtils
  alias Exdock.ReadModel

  @impl true
  def update(%{containers: containers, containers_revision: revision} = assigns, socket) do
    containers_changed? = socket.assigns[:containers_revision] != revision

    rows = if containers_changed?, do: build_rows(containers, assigns.id), else: []
    active_manager = active_manager(containers, assigns.nodename, assigns[:active_modal_id])
    containers_count = if containers_changed?, do: length(rows), else: socket.assigns.containers_count

    socket =
      socket
      |> assign(Map.drop(assigns, [:containers]))
      |> assign(:containers_count, containers_count)
      |> assign(:active_manager, active_manager)

    socket =
      if containers_changed?,
        do: stream(socket, :container_rows, rows, reset: true),
        else: socket

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={@outerdivclass} id={@id}>
      <.containers_table
        parent_id={@id}
        headlinetext={@headlinetext}
        container_rows={@streams.container_rows}
        active_manager={@active_manager}
        containers_count={@containers_count}
        nodename={@nodename}
        is_outdated={@is_outdated}
        is_running={@is_running}
        repositories={@repositories}
        clock_now={@clock_now}
      />
    </div>
    """
  end

  defp containers_table(assigns) do
    ~H"""
    <div :if={@containers_count > 0}>
      <div class="container-group-header">
        <div class="flex min-w-0 items-center gap-2">
          <span class="container-group-status-dot"></span>
          <h2
            id={"#{@parent_id}-title"}
            class="truncate font-mono text-xs font-bold capitalize tracking-wide text-high-visibility"
          >
            {@headlinetext}
          </h2>
          <span class="container-group-count" aria-label={"#{@containers_count} containers"}>
            {@containers_count}
          </span>
        </div>

        <button
          id={"#{@parent_id}-hide-button"}
          type="button"
          class="container-group-hide-action"
          phx-click={hide_modal(@parent_id)}
          title={"Remove #{@headlinetext} view"}
        >
          <.icon name="hero-x-mark" class="size-3" />
          <span>remove view</span>
        </button>
      </div>

      <table
        id={"#{@parent_id}-table"}
        class="node-containers-table"
        aria-labelledby={"#{@parent_id}-title"}
      >
        <thead>
          <tr>
            <th class="w-16 text-center">Priority</th>

            <th class="min-w-40">Name</th>

            <th class="min-w-32">Stack</th>

            <th class="min-w-52">Image</th>

            <th class="w-20 text-right">Size</th>

            <%= if @is_outdated do %>
              <th class="w-24 text-center">Pulled</th>
            <% end %>

            <th class="min-w-52">Build Date</th>

            <th class="min-w-72">Resources</th>

            <th class="w-20 text-center">{if @is_running, do: "Uptime", else: "Downtime"}</th>

            <th class="w-16">
              <span class="sr-only">State and network</span>
            </th>
          </tr>
        </thead>

        <tbody
          id={"#{@parent_id}-rows"}
          phx-update="stream"
          class="whitespace-nowrap"
        >
          <%= for {id, row} <- @container_rows do %>
            <ExdockWeb.ContainersLive.ContainerListRow.render
              id={id}
              nodename={@nodename}
              name={row.key.name}
              core={row.core}
              extended={row.extended}
              is_outdated={@is_outdated}
              is_running={row.core.is_running}
              clock_now={@clock_now}
            />
          <% end %>
        </tbody>
      </table>

      <div :if={@active_manager} id={"#{@parent_id}-manager"}>
        <.live_component
          module={ExdockWeb.Commons.ContainerManager}
          id={IdUtils.create_id("container_manager_list_#{@nodename}_#{@active_manager.key.name}")}
          modal_id={IdUtils.container_manager_id(@nodename, @active_manager.key.name)}
          component_id={IdUtils.create_id("container_manager_list_component_#{@nodename}_#{@active_manager.key.name}")}
          render?={true}
          nodename={@nodename}
          container_name={@active_manager.key.name}
          core={@active_manager.core}
          extended={@active_manager.extended}
          release_data={ReadModel.repository_data(@repositories, @active_manager.core.repository_url)}
          clock_now={@clock_now}
        />
      </div>
    </div>
    """
  end

  defp active_manager(containers, nodename, active_modal_id) do
    Enum.find_value(containers, fn {key, core, extended} ->
      if IdUtils.container_manager_id(nodename, key.name) == active_modal_id,
        do: %{key: key, core: core, extended: extended}
    end)
  end

  defp build_rows(containers, component_id) do
    Enum.map(containers, fn {key, core, extended} ->
      %{
        id: IdUtils.create_id("#{component_id}-#{key.name}"),
        key: key,
        core: core,
        extended: extended
      }
    end)
  end
end
