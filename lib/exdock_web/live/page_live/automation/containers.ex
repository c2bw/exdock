defmodule ExdockWeb.Automation.Containers do
  use ExdockWeb, :live_component
  alias Exdock.Container.AutomationPolicy
  alias Exdock.ReadModel.Container
  alias ExdockWeb.ContainerPolicyControls
  alias ExdockWeb.PageLive.Utils.ContainerSettingsEvents
  alias ExdockWeb.PageLive.Utils.IdUtils
  alias ExdockWeb.PageLive.Utils.LiveOperation

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id <> "-panel"} class="automation-panel">
      <header class="automation-panel-header">
        <div class="flex min-w-0 items-center gap-3">
          <span class="control-icon-tile automation-panel-icon" aria-hidden="true">
            <.icon name="hero-server-stack" class="h-5 w-5" />
          </span>
          <div class="min-w-0">
            <h2 class="automation-panel-title">Container policies</h2>
            <p class="automation-panel-description">
              Choose which running containers participate in automatic updates.
            </p>
          </div>
        </div>

        <div class="flex items-center gap-2" aria-label="Automation container summary">
          <span class="automation-stat-pill">
            <strong>{@enabled_count}</strong> enabled
          </span>
          <span class="automation-stat-pill">
            <strong>{@outdated_count}</strong> outdated
          </span>
        </div>
      </header>

      <div class="automation-panel-body">
        <p class="mb-3 text-xs font-mono text-low-visibility">
          Automation is enabled for <span class="font-semibold text-mid-visibility">{@enabled_count}</span>
          containers, with <span class="font-semibold text-mid-visibility">{@outdated_count}</span>
          currently outdated.
        </p>

        <div class="automation-table-frame w-full min-w-fit">
          <table class="automation-table m-0 table-auto">
            <thead>
              <tr>
                <th scope="col" class="w-28 text-center">Status</th>

                <th scope="col">Node</th>

                <th scope="col">Name</th>

                <th scope="col" class="text-center">Update policy</th>
              </tr>
            </thead>

            <tbody id="automation-container-rows" phx-update="stream" class="whitespace-nowrap">
              <%= for {id, row} <- @streams.containers do %>
                <.row
                  id={id}
                  node={row.node}
                  name={row.name}
                  update_policy={row.update_policy}
                  to_update={row.to_update}
                  is_outdated={row.image_status == :outdated}
                  row_class={[
                    "automation-container-row--policy-#{row.update_policy}",
                    if(row.to_update,
                      do: "automation-container-row--enabled",
                      else: "automation-container-row--inactive"
                    )
                  ]}
                  target={@myself}
                />
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    """
  end

  defp row(assigns) do
    ~H"""
    <tr id={@id} class={@row_class}>
      <td class="w-28 text-center">
        <%= if @to_update and @is_outdated do %>
          <span class="automation-outdated-indicator">
            <.icon name="hero-arrow-up-circle" class="h-4 w-4" /> outdated
          </span>
        <% else %>
          <span class="text-xxs text-low-visibility">—</span>
        <% end %>
      </td>

      <td>{@node}</td>

      <td class="font-semibold text-high-visibility">{@name}</td>

      <td>
        <ContainerPolicyControls.auto_update_stepper
          id={@id <> "-auto-update"}
          node={@node}
          container={@name}
          current_policy={@update_policy}
          target={@target}
        />
      </td>
    </tr>
    """
  end

  @impl true
  def update(%{containers: containers, required_priority: required_priority} = assigns, socket) do
    rows = container_rows(containers, required_priority)

    socket =
      socket
      |> assign(Map.drop(assigns, [:containers]))
      |> assign(
        enabled_count: Enum.count(rows, & &1.to_update),
        outdated_count: Enum.count(rows, &(&1.to_update && &1.image_status == :outdated))
      )
      |> stream(:containers, rows, reset: true)

    {:ok, socket}
  end

  defp container_rows(core_map, required_priority) do
    Enum.reduce(core_map, [], fn {node, node_map}, acc ->
      Enum.reduce(node_map, acc, fn container_entry, acc ->
        case container_row(container_entry, required_priority) do
          nil ->
            acc

          {name, image_status, update_policy, to_update} ->
            [
              %{
                id: IdUtils.create_id("automation-container-#{node}-#{name}"),
                node: node,
                name: name,
                image_status: image_status,
                update_policy: update_policy,
                to_update: to_update
              }
              | acc
            ]
        end
      end)
    end)
    |> Enum.sort_by(&{&1.node, &1.name})
  end

  defp container_row(%{} = container, required_priority) do
    if Container.running?(container) do
      settings = Container.settings(container)
      update = AutomationPolicy.participates?(settings.priority, settings.auto_update, required_priority)

      {container.name, Container.image_status(container), settings.auto_update, update}
    end
  end

  @impl true
  def handle_event("change_auto_update", params, socket) do
    result = ContainerSettingsEvents.change_auto_update(params)
    {:noreply, ContainerSettingsEvents.apply_auto_update_result(socket, result)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, LiveOperation.invalid_component(socket)}
end
