defmodule ExdockWeb.ContainersLive.ContainerListRow do
  use ExdockWeb, :html

  alias ExdockWeb.ContainersLive.ContainerListRow.{
    BuildCell,
    ResourcesCell,
    StateCell,
    ViewModel
  }

  alias ExdockWeb.PageLive.Utils.IdUtils
  attr :id, :string, required: true
  attr :nodename, :any, required: true
  attr :name, :string, required: true
  attr :core, :any, required: true
  attr :extended, :any, required: true
  attr :is_outdated, :boolean, required: true
  attr :is_running, :boolean, required: true
  attr :clock_now, :any, required: true

  def render(assigns) do
    assigns = assign(assigns, :row, ViewModel.build(assigns))

    ~H"""
    <tr
      id={@id}
      class={["node-container-row", @row.error? && "node-container-row--error"]}
      phx-click={show_lazy_modal(IdUtils.container_manager_id(@nodename, @name))}
    >
      <td class="container-priority-cell">
        <span class={["container-priority-badge", @row.priority_class]}>
          {@row.priority}
        </span>
      </td>

      <td class="container-name-cell" title={@name}>{@row.name}</td>
      <td class="container-stack-cell" title={@core.stack_name}>{@row.stack_name}</td>

      <td class="container-image-cell" title={@core.image_tag}>
        <a
          class="container-image-link"
          href={@row.image_url}
          target="_blank"
          rel="noreferrer"
          phx-click=""
        >
          {@row.image_tag}
        </a>
      </td>

      <td class="container-size-cell">{@row.image_size}</td>

      <td :if={@is_outdated} class="container-pull-cell">
        <%= case @row.pull_state do %>
          <% :present -> %>
            <.icon name="hero-check-circle" class="size-4 shrink-0 text-success-icon" />
            <button class="container-pull-action btn-disabled" disabled>
              <.icon name="hero-chevron-double-down" class="size-3" /> Pull
            </button>
          <% :available -> %>
            <.icon name="hero-no-symbol" class="size-4 shrink-0 text-error" />
            <button
              id={@id <> "-pull-image"}
              class="container-pull-action container-pull-action--available"
              phx-click={
                Phoenix.LiveView.JS.push("image-pull",
                  value: %{node: @nodename, image_tag: @core.image_tag}
                )
              }
            >
              <.icon name="hero-chevron-double-down" class="size-3" /> Pull
            </button>
        <% end %>
      </td>

      <td class="container-build-cell">
        <BuildCell.render build={@row.build} />
      </td>

      <td class="container-resources-cell">
        <ResourcesCell.render metrics={@row.resources} />
      </td>

      <td class="container-duration-cell">
        <span class="container-duration">{@row.duration}</span>
      </td>

      <td class="container-state-cell">
        <StateCell.render lifecycle={@row.lifecycle} network={@row.network} />
      </td>
    </tr>
    """
  end
end
