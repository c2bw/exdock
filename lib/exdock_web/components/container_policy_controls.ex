defmodule ExdockWeb.ContainerPolicyControls do
  @moduledoc """
  Shared controls for editing per-container priority and auto-update policy.

  Every caller emits the same event parameter shape so validation and operation
  handling remain independent of the page that renders the control.
  """

  use ExdockWeb, :html

  attr :id, :string, required: true
  attr :node, :string, required: true
  attr :container, :string, required: true
  attr :priority, :integer, required: true
  attr :target, :any, required: true
  attr :variant, :atom, default: :default, values: [:default, :compact]

  def priority_stepper(assigns) do
    ~H"""
    <div id={@id} class={["flex items-center justify-center", priority_gap(@variant)]}>
      <button
        id={@id <> "-decrease"}
        type="button"
        aria-label={"Decrease priority for #{@container}"}
        class={button_class(@variant)}
        phx-click="change_priority"
        phx-value-node={@node}
        phx-value-container={@container}
        phx-value-priority={Kernel.max(1, @priority - 1)}
        phx-target={@target}
      >
        <.icon name="hero-minus" class="h-4 w-4" />
      </button>

      <span class={priority_value_class(@variant)}>{@priority}</span>

      <button
        id={@id <> "-increase"}
        type="button"
        aria-label={"Increase priority for #{@container}"}
        class={button_class(@variant)}
        phx-click="change_priority"
        phx-value-node={@node}
        phx-value-container={@container}
        phx-value-priority={Kernel.min(5, @priority + 1)}
        phx-target={@target}
      >
        <.icon name="hero-plus" class="h-4 w-4" />
      </button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :node, :string, required: true
  attr :container, :string, required: true
  attr :current_policy, :atom, required: true
  attr :target, :any, required: true
  attr :variant, :atom, default: :default, values: [:default, :compact]

  def auto_update_stepper(assigns) do
    ~H"""
    <div id={@id} class="flex items-center justify-center gap-2">
      <button
        id={@id <> "-previous"}
        type="button"
        aria-label={"Previous auto-update policy for #{@container}"}
        class={button_class(@variant)}
        phx-click="change_auto_update"
        phx-value-node={@node}
        phx-value-container={@container}
        phx-value-current-policy={@current_policy}
        phx-value-next="prev"
        phx-target={@target}
      >
        <.icon name="hero-chevron-left" class="h-4 w-4" />
      </button>

      <span
        class={[auto_update_value_class(@variant), "capitalize"]}
        title={to_string(@current_policy)}
        aria-live="polite"
      >
        {@current_policy}
      </span>

      <button
        id={@id <> "-next"}
        type="button"
        aria-label={"Next auto-update policy for #{@container}"}
        class={button_class(@variant)}
        phx-click="change_auto_update"
        phx-value-node={@node}
        phx-value-container={@container}
        phx-value-current-policy={@current_policy}
        phx-value-next="next"
        phx-target={@target}
      >
        <.icon name="hero-chevron-right" class="h-4 w-4" />
      </button>
    </div>
    """
  end

  defp button_class(:compact) do
    "grid h-7 w-7 place-items-center rounded-md border border-secondary text-mid-visibility transition hover:border-primary hover:bg-secondary hover:text-high-visibility"
  end

  defp button_class(:default) do
    "grid h-7 w-7 place-items-center rounded-md border border-primary bg-primary-lighter text-mid-visibility transition hover:bg-secondary hover:text-high-visibility"
  end

  defp priority_gap(:compact), do: "gap-1"
  defp priority_gap(:default), do: "gap-2"

  defp priority_value_class(:compact),
    do: "w-8 shrink-0 text-center text-sm font-semibold text-high-visibility"

  defp priority_value_class(:default),
    do: "min-w-20 text-center text-xs font-semibold text-mid-visibility"

  defp auto_update_value_class(:compact),
    do:
      "w-20 min-w-20 shrink-0 truncate text-center text-xs font-semibold text-high-visibility transition-[font-size] duration-150"

  defp auto_update_value_class(:default),
    do: "min-w-20 text-center text-xs font-semibold text-mid-visibility"
end
