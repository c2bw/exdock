defmodule ExdockWeb.HomepageLive.MassContainerManager.PriorityRowAction do
  use ExdockWeb, :html

  @actions %{
    pull: %{
      event: "image-pull",
      label: "Pull",
      icons: [
        {"hero-arrow-down-tray", "h-3.5 w-3.5 transition-transform duration-200 group-hover/action:translate-y-0.5"}
      ],
      show_label?: true,
      emphasis: "text-mid-visibility",
      image_pull: nil
    },
    recreate: %{
      event: "container-recreate",
      label: "Recreate",
      icons: [
        {"hero-arrow-path-rounded-square",
         "h-3.5 w-3.5 transition-transform duration-300 group-hover/action:rotate-45 phx-click-loading:animate-spin"}
      ],
      show_label?: true,
      emphasis: "text-mid-visibility",
      image_pull: "false"
    },
    pull_and_recreate: %{
      event: "container-recreate",
      label: "Pull and recreate",
      icons: [
        {"hero-arrow-down-tray", "h-3.5 w-3.5 transition-transform duration-200 group-hover/action:translate-y-0.5"},
        {"hero-arrow-path-rounded-square",
         "h-3.5 w-3.5 transition-transform duration-300 group-hover/action:rotate-45 phx-click-loading:animate-spin"}
      ],
      show_label?: false,
      emphasis: "bg-secondary text-eye",
      image_pull: "true"
    }
  }

  attr :id, :string, required: true
  attr :action, :atom, values: Map.keys(@actions), required: true
  attr :jobs, :list, required: true

  def render(assigns) do
    action = Map.fetch!(@actions, assigns.action)
    assigns = assigns |> assign(action) |> assign(:payload, action_payload(assigns.action, assigns.jobs))

    ~H"""
    <div id={@id} class="flex h-7 shrink-0">
      <button
        type="button"
        class={[
          "group/action inline-flex h-full items-center justify-center gap-1.5 whitespace-nowrap px-2.5 font-mono text-[0.6875rem] font-semibold",
          "transition-all duration-150 bg-hover text-hover-eye active:translate-y-px active:bg-[var(--surface-base)]",
          "focus-visible:z-10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent)]",
          "phx-click-loading:pointer-events-none phx-click-loading:opacity-60",
          @emphasis
        ]}
        phx-click={Phoenix.LiveView.JS.push(@event, value: @payload)}
        aria-label={@label}
        title={@label}
      >
        <.icon :for={{name, class} <- @icons} name={name} class={class} />
        <span :if={@show_label?} class="max-lg:hidden">{@label}</span>
      </button>
    </div>
    """
  end

  defp action_payload(:pull, jobs), do: %{images: jobs}
  defp action_payload(:recreate, jobs), do: %{containers: jobs, image_pull: false}
  defp action_payload(:pull_and_recreate, jobs), do: %{containers: jobs, image_pull: true}
end
