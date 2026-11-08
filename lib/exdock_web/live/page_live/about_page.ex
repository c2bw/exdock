defmodule ExdockWeb.PageLive.AboutPage do
  @moduledoc """
  Lazy-rendered about modal content for the Exdock UI.

  The modal is mounted by pages only after the shared lazy-modal event marks it
  as renderable.
  """

  use ExdockWeb, :html

  def render(assigns) do
    ~H"""
    <div class="overflow-auto">
      <p class="modal-title">About Exdock</p>

      <p class="modal-content">
        Exdock aims to be a simple interface to assist in the process of monitoring and updating your Docker containers across multiple nodes.
      </p>

      <p class="modal-title">How to use</p>

      <p class="modal-content">
        <span class="font-semibold">Nodes</span>
        <br />The data is retrieved when a client connects to the Exdock server, external changes on the node will require a
        <span class="font-semibold italic">refresh</span>
        to view the latest data.
      </p>

      <p class="modal-content mt-4">
        <span class="font-semibold">Images</span> <br /> Use the <span class="font-semibold italic">fetch registry</span>
        button to retrieve the latest remote information.
      </p>

      <p class="modal-content mt-4">
        <span class="font-semibold">General Info</span>
        <ul class="mt-0 pt-0 list-disc pl-6 text-mid-visibility font-mono tracking-tighter">
          <li>
            The containers are categorized by the status of their image: <span class="font-semibold italic">updated</span>,
            <span class="font-semibold italic">outdated</span>
            or <span class="font-semibold italic">unknown</span>. For further intracategory ordering use the
            <span class="font-semibold">priority</span>
            feature.
          </li>

          <li>
            The <span class="font-semibold">repository URL</span> is inferred using the image tag but it can be manually overridden.
          </li>

          <li>
            Setup automatic registry and containers updates using the <span class="font-semibold">automation</span> page.
          </li>
        </ul>
      </p>

      <p class="modal-content mt-4">
        <span class="font-semibold">Warning Notes</span> <br />
        Although stable, the current product is still in early development, for critical infrastructure it is recommended to use the Docker CLI or a more advanced tool.
      </p>

      <p class="modal-title mt-4">Icons Legend</p>

      <div class="mt-0 flex flex-col gap-y-2 gap-x-4">
        <div class="flex flex-row flex-wrap gap-3">
          <.legend_icon icon="hero-command-line" icon_color="text-low-visibility" text="Job in progress" />
          <.legend_icon icon="hero-calendar" icon_color="text-low-visibility" text="Job is automated" />
        </div>

        <div class="flex flex-row flex-wrap gap-3">
          <.legend_icon icon="hero-check-circle" icon_color="text-success-icon" text="Latest image is present on node" />
          <.legend_icon icon="hero-no-symbol" icon_color="text-error" text="Latest image is NOT present on node" />
        </div>

        <div class="flex flex-row flex-wrap gap-3">
          <.legend_icon icon="hero-clock" icon_color="text-success" text="Data recently fetched" />
          <.legend_icon icon="hero-clock" icon_color="text-warning" text="Data is stale" />
          <.legend_icon icon="hero-clock" icon_color="text-amber-600" text="Data is old" />
        </div>

        <div class="flex flex-row flex-wrap gap-3">
          <.legend_icon icon="hero-cog" icon_color="text-success" text="Container is running" />
          <.legend_icon icon="hero-cog" icon_color="text-high-visibility" text="Container is not running" />
          <.legend_icon icon="hero-cog" icon_color="text-warning" text="Container started recently" />
          <.legend_icon icon="hero-cog" icon_color="text-eye-secondary" text="Container is restarting" />
        </div>

        <div class="flex flex-row flex-wrap gap-3">
          <.legend_icon icon="hero-globe-alt" icon_color="text-mid-visibility" text="Container has published ports" />
        </div>
      </div>
    </div>
    """
  end

  defp legend_icon(assigns) do
    ~H"""
    <div class="flex">
      <p class="text-center text-xs font-mono tracking-tighter text-mid-visibility whitespace-nowrap">
        <.icon name={@icon} class={["w-5 h-5 mb-1 mr-1", @icon_color]} />{@text}
      </p>
    </div>
    """
  end
end
