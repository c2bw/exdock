defmodule ExdockWeb.Commons.NodeSummary.Actions do
  @moduledoc "Stateless external-link and node-action presentation."

  use ExdockWeb, :html

  attr :model, :map, required: true
  attr :modal_id, :string, required: true

  def render(assigns) do
    ~H"""
    <div class="ms-1 flex w-72 grow shrink-0 justify-end max-2xl:w-44">
      <div class="flex items-center justify-end gap-1.5 pe-3">
        <div :if={@model.actions.web_ui != ""} class="flex items-center" phx-click="">
          <a
            href={@model.actions.web_ui}
            target="_blank"
            rel="noreferrer"
            class="btn-secondary inline-flex h-8 items-center gap-1.5 px-2.5 text-low-visibility text-hover-high-visibility"
            title="Open node web UI"
          >
            <span class="font-mono text-xs max-2xl:hidden">Web UI</span>
            <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" />
          </a>
        </div>

        <button
          type="button"
          class="btn-secondary inline-flex h-8 w-8 items-center justify-center p-0"
          phx-click={show_modal(@modal_id)}
          aria-label="Configure node"
          title="Configure node"
        >
          <.icon name="hero-adjustments-vertical" class="h-4 w-4" />
        </button>

        <button
          :if={@model.actions.registry_fetch?}
          type="button"
          phx-click="registry_fetch_node"
          phx-value-nodename={@model.actions.nodename}
          class="btn-secondary inline-flex h-8 w-8 items-center justify-center p-0"
          aria-label="Fetch node registry"
          title="Fetch node registry"
        >
          <.icon name="hero-bars-arrow-down" class="h-4 w-4" />
        </button>

        <button
          type="button"
          phx-click="node_refresh"
          phx-value-nodename={@model.actions.nodename}
          class="btn-primary inline-flex h-8 w-8 items-center justify-center p-0"
          aria-label="Refresh node"
          title="Refresh node"
        >
          <.icon name="hero-arrow-path" class="h-4 w-4 transition-transform duration-300 hover:rotate-45" />
        </button>
      </div>
    </div>
    """
  end
end
