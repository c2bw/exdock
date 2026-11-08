defmodule ExdockWeb.HomepageLive.MassContainerManager do
  use ExdockWeb, :live_component
  alias ExdockWeb.PageLive.HomepageLive.Utils.Container
  alias ExdockWeb.PageLive.Utils.IdUtils
  alias Exdock.Size
  alias Exdock.ReadModel
  alias ExdockWeb.HomepageLive.MassContainerManager.PriorityGroup

  @impl true
  def update(%{containers: containers, containers_revision: revision} = assigns, socket) do
    groups =
      if socket.assigns[:containers_revision] == revision do
        socket.assigns.groups
      else
        PriorityGroup.from_snapshot(containers)
      end

    socket =
      socket
      |> assign(Map.drop(assigns, [:containers]))
      |> assign(:groups, groups)
      |> assign(:active_manager, active_manager(groups, assigns[:active_modal_id]))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-w-0 overflow-hidden">
      <header class="mb-4 border-b border-primary px-10 pb-3 text-center">
        <div class="mx-auto min-w-0">
          <h2
            id="mass-container-manager-title"
            class="font-mono text-base font-semibold tracking-tight text-high-visibility"
          >
            Mass Container Manager
          </h2>

          <p
            id="mass-container-manager-description"
            class="mt-0.5 text-[0.6875rem] leading-4 text-low-visibility"
          >
            <span class="font-medium text-container-outdated">Out-of-date</span> running containers, grouped by priority.
          </p>
        </div>
      </header>

      <ul class="space-y-1.5">
        <%= for group <- @groups do %>
          <.priority_row
            group={group}
            containers_extended={@containers_extended}
            repositories={@repositories}
          />
        <% end %>
      </ul>

      <%= if @active_manager do %>
        <.live_component
          module={ExdockWeb.Commons.ContainerManager}
          id={IdUtils.create_id("container_manager_mass_#{@active_manager.node}_#{@active_manager.key.name}")}
          modal_id={@active_manager.modal_id}
          component_id={IdUtils.create_id("container_manager_mass_component_#{@active_manager.node}_#{@active_manager.key.name}")}
          render?={true}
          nodename={@active_manager.node}
          container_name={@active_manager.key.name}
          core={@active_manager.core}
          extended={Container.get_container_extended(@containers_extended, @active_manager.node, @active_manager.key)}
          release_data={ReadModel.repository_data(@repositories, @active_manager.core.repository_url)}
          clock_now={@clock_now}
        />
      <% end %>
    </div>
    """
  end

  defp priority_row(assigns) do
    ~H"""
    <li class="min-w-0">
      <details
        class="group overflow-hidden rounded-lg border border-primary bg-see-through transition-colors open:bg-primary"
        id={"masscontainermanagerpriority#{@group.priority}"}
        phx-hook="CollapsibleState"
      >
        <summary
          class="flex min-h-12 cursor-pointer list-none flex-wrap items-center justify-between gap-x-3 gap-y-1 px-2 py-1 transition-colors bg-hover"
          id={"masscontainermanagerprioritysummary#{@group.priority}"}
        >
          <div class="min-w-0 basis-64 flex-1 overflow-hidden">
            <table class="m-0 w-full max-w-sm table-fixed font-mono">
              <thead class="whitespace-nowrap text-[0.5625rem] font-semibold uppercase tracking-wider text-low-visibility">
                <tr>
                  <th class="px-1.5 pb-0.5 text-center">Priority</th>

                  <th class="px-1.5 pb-0.5 text-center">Containers</th>

                  <th class="px-1.5 pb-0.5 text-center">Size</th>
                </tr>
              </thead>

              <tbody class="whitespace-nowrap text-xs font-semibold text-high-visibility">
                <tr>
                  <td class="truncate border-t border-secondary px-1.5 pt-0.5 text-center tabular-nums">
                    {@group.priority}
                  </td>

                  <td class="truncate border-t border-secondary px-1.5 pt-0.5 text-center tabular-nums">
                    {length(@group.containers)}
                  </td>

                  <td class="truncate border-t border-secondary px-1.5 pt-0.5 text-center tabular-nums">
                    {@group.image_size |> Size.human_readable()}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="ml-auto flex items-center gap-1.5 font-mono">
            <div
              class="first-divider-subtle-x flex items-center divide-x divide-primary overflow-hidden rounded-lg border border-primary bg-primary-lighter shadow-sm"
              role="group"
              aria-label={"Bulk actions for priority #{@group.priority}"}
            >
              <ExdockWeb.HomepageLive.MassContainerManager.PriorityRowAction.render
                id={IdUtils.create_id("container_manager_priority_pull_#{@group.priority}")}
                action={:pull}
                jobs={@group.pull_jobs}
              />
              <ExdockWeb.HomepageLive.MassContainerManager.PriorityRowAction.render
                id={IdUtils.create_id("container_manager_priority_recreate_#{@group.priority}")}
                action={:recreate}
                jobs={@group.recreate_jobs}
              />
              <ExdockWeb.HomepageLive.MassContainerManager.PriorityRowAction.render
                id={IdUtils.create_id("container_manager_priority_pullandrecreate_#{@group.priority}")}
                action={:pull_and_recreate}
                jobs={@group.recreate_jobs}
              />
            </div>

            <.icon
              name="hero-chevron-right"
              class="h-4 w-4 shrink-0 text-low-visibility transition-transform duration-200 group-open:rotate-90"
            />
          </div>
        </summary>

        <div class="max-h-64 grow overflow-auto border-t border-primary bg-primary">
          <table class="m-0 w-full min-w-[34rem] table-auto font-mono">
            <thead class="sticky top-0 z-10 whitespace-nowrap bg-secondary text-[0.5625rem] font-semibold uppercase tracking-wider text-low-visibility">
              <tr class="text-left">
                <th class="w-12 px-3 py-1.5 text-center">Local</th>

                <th class="px-3 py-1.5">Node</th>

                <th class="px-3 py-1.5">Name</th>

                <th class="px-3 py-1.5">Image</th>

                <th class="px-3 py-1.5 text-right">Size</th>
              </tr>
            </thead>

            <tbody class="first-row-divider-subtle divide-y divide-primary whitespace-nowrap">
              <%= for {node, key, core} <- @group.containers do %>
                <ExdockWeb.HomepageLive.MassContainerManager.ContainerRow.render
                  id={IdUtils.create_id("container_manager_mass_row_#{node}_#{key.name}")}
                  node={node}
                  key={key}
                  core={core}
                  image_present_on_node={core.image_present_on_node}
                />
              <% end %>
            </tbody>
          </table>
        </div>
      </details>
    </li>
    """
  end

  defp active_manager(groups, active_modal_id) do
    groups
    |> Enum.flat_map(& &1.containers)
    |> Enum.find_value(fn {node, key, core} ->
      modal_id = "#{IdUtils.container_manager_id(node, key.name)}mass"

      if modal_id == active_modal_id do
        %{node: node, key: key, core: core, modal_id: modal_id}
      end
    end)
  end
end
