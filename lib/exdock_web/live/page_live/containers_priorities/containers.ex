defmodule ExdockWeb.ContainersPriorities.Containers do
  use ExdockWeb, :live_component
  alias Exdock.ReadModel.Container
  alias ExdockWeb.ContainerPolicyControls
  alias ExdockWeb.PageLive.Utils.{ContainerSettingsEvents, IdUtils, LiveOperation}
  alias ExdockWeb.Presentation.Container, as: ContainerPresentation

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-4 flex flex-col space-y-4">
      <div class="flex flex-row">
        <div class="flex">
          <p class="text-mid-visibility text-sm font-mono">
            Custom containers priorities {@custom_priorities_count}
          </p>
        </div>

        <div class="flex">
          <%= if @hide_default do %>
            <button
              class="ms-2 py-0 px-4 text-xs bg-disabled font-semibold font-mono text-mid-visibility text-hover-high-visibility rounded ring-1 ring-primary"
              phx-click="toggle_default_priorities_visibility"
              phx-target={@myself}
            >
              hiding default
            </button>
          <% else %>
            <button
              class="ms-2 py-0 px-4 text-xs bg-enabled font-semibold font-mono text-mid-visibility text-hover-high-visibility rounded ring-1 ring-primary"
              phx-click="toggle_default_priorities_visibility"
              phx-target={@myself}
            >
              showing default
            </button>
          <% end %>
        </div>
      </div>

      <div class="space-y-2 w-full min-w-fit">
        <table class="m-0 table-auto text-center w-full font-mono bg-see-through">
          <thead class="text-sm text-left leading-6 text-high-visibility border-y-2 border-secondary">
            <tr class="">
              <th class="border-r border-secondary ps-1 pe-1 text-xs">Node</th>

              <th class="border border-secondary ps-2 pe-2">Name</th>

              <th class="border border-secondary ps-2 pe-2">Priority</th>
            </tr>
          </thead>

          <tbody
            id="priority-container-rows"
            phx-update="stream"
            class="first-row-divider-subtle divide-y divide-primary whitespace-nowrap"
          >
            <%= for {id, row} <- @streams.containers do %>
              <.row
                id={id}
                node={row.node}
                name={row.name}
                priority={row.priority}
                target={@myself}
                bg_color={ContainerPresentation.priority_class(row.priority)}
              />
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp row(assigns) do
    ~H"""
    <tr id={@id} class={["text-sm text-left leading-6 text-high-visibility pb-2 bg-hover-tertiary", @bg_color]}>
      <td class="ps-2 pe-2 text-xs">{@node}</td>

      <td class="ps-2 pe-2 text-xs">{@name}</td>

      <td class="ps-2 pe-2 text-xs">
        <ContainerPolicyControls.priority_stepper
          id={@id <> "-priority"}
          node={@node}
          container={@name}
          priority={@priority}
          target={@target}
        />
      </td>
    </tr>
    """
  end

  defp container_rows(core_map) do
    Enum.reduce(core_map, [], fn {node, node_map}, acc ->
      Enum.reduce(node_map, acc, fn container_entry, acc ->
        {name, priority} = container_priority(container_entry)

        [
          %{
            id: IdUtils.create_id("priority-container-#{node}-#{name}"),
            node: node,
            name: name,
            priority: priority
          }
          | acc
        ]
      end)
    end)
    |> Enum.sort_by(&{&1.node, &1.name})
  end

  defp container_priority(%{name: name} = container), do: {name, Container.priority(container)}

  defp visible_rows(rows, true = _hide_default), do: Enum.reject(rows, &(&1.priority == 3))
  defp visible_rows(rows, false = _hide_default), do: rows

  @impl true
  def update(%{containers: containers} = assigns, socket) do
    hide_default = socket.assigns[:hide_default] || false
    rows = container_rows(containers)

    socket =
      socket
      |> assign(Map.drop(assigns, [:containers]))
      |> assign(
        hide_default: hide_default,
        container_rows: rows,
        custom_priorities_count: Enum.count(rows, &(&1.priority != 3))
      )
      |> stream(:containers, visible_rows(rows, hide_default), reset: true)

    {:ok, socket}
  end

  @impl true
  def handle_event("change_priority", params, socket) do
    result = ContainerSettingsEvents.change_priority(params)
    {:noreply, ContainerSettingsEvents.apply_priority_result(socket, result)}
  end

  def handle_event("toggle_default_priorities_visibility", _, socket) do
    hide_default = !socket.assigns.hide_default

    socket =
      socket
      |> assign(:hide_default, hide_default)
      |> stream(:containers, visible_rows(socket.assigns.container_rows, hide_default), reset: true)

    {:noreply, socket}
  end

  def handle_event(_event, _params, socket), do: {:noreply, LiveOperation.invalid_component(socket)}
end
