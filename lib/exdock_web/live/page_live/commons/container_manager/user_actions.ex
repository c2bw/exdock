defmodule ExdockWeb.Commons.ContainerManager.UserActions do
  use Phoenix.Component
  import ExdockWeb.CoreComponents
  alias Exdock.Container.Policy

  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :disabled, :boolean, default: false
  attr :tone, :string, default: "default"

  defp action_button(assigns) do
    ~H"""
    <button
      type="submit"
      disabled={@disabled}
      class={[
        "group inline-flex h-9 items-center justify-center gap-2 rounded-lg border px-3 text-xs font-semibold shadow-sm transition-all",
        "active:translate-y-px disabled:cursor-not-allowed disabled:opacity-45 disabled:shadow-none",
        @tone == "default" &&
          "border-primary bg-primary-lighter text-mid-visibility hover:border-[var(--accent)] hover:bg-secondary hover:text-high-visibility",
        @tone == "accent" && "border-[var(--accent)] bg-[var(--accent)] text-core-component hover:brightness-110"
      ]}
    >
      <.icon name={@icon} class="h-4 w-4 transition-transform group-hover:scale-105" /> <span>{@label}</span>
    </button>
    """
  end

  attr :id, :string, required: true
  attr :nodename, :any, required: true
  attr :container_name, :string, required: true
  attr :core, :map, required: true
  attr :action_form, :any, required: true
  attr :myself, :any, required: true

  def render(assigns) do
    ~H"""
    <div id={@id <> "actions"} class="mt-5 border-t border-primary pt-4">
      <div class="flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between">
        <div>
          <p class="text-xs font-semibold text-high-visibility">Container actions</p>

          <p class="mt-0.5 text-[0.675rem] text-low-visibility">Lifecycle operations are applied immediately.</p>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <.form for={@action_form} id={@id <> "start-form"} phx-submit="container-start">
            <.input type="hidden" field={@action_form[:node]} id={@id <> "start_node"} value={@nodename} />
            <.input type="hidden" field={@action_form[:container_name]} id={@id <> "start_container"} value={@container_name} />
            <.action_button label="Start" icon="hero-play" disabled={@core.is_running or @core.state.restarting} />
          </.form>

          <.form for={@action_form} id={@id <> "stop-form"} phx-submit="container-stop">
            <.input type="hidden" field={@action_form[:node]} id={@id <> "stop_node"} value={@nodename} />
            <.input type="hidden" field={@action_form[:container_name]} id={@id <> "stop_container"} value={@container_name} />
            <.action_button label="Stop" icon="hero-stop" disabled={not (@core.is_running or @core.state.restarting)} />
          </.form>

          <.form for={@action_form} id={@id <> "restart-form"} phx-submit="container-restart">
            <.input type="hidden" field={@action_form[:node]} id={@id <> "restart_node"} value={@nodename} />
            <.input type="hidden" field={@action_form[:container_name]} id={@id <> "restart_container"} value={@container_name} />
            <.action_button label="Restart" icon="hero-arrow-path" disabled={not @core.is_running} />
          </.form>

          <div class="flex items-center gap-2 rounded-lg border border-primary bg-primary-lighter p-1">
            <.form for={@action_form} id={@id <> "recreate-form"} phx-submit="container-recreate">
              <.input
                type="hidden"
                field={@action_form[:node]}
                id={@id <> "recreate_nodename"}
                value={@nodename}
              />
              <.input
                type="hidden"
                field={@action_form[:container_name]}
                id={@id <> "recreate_container_name"}
                value={@container_name}
              />
              <.input
                type="hidden"
                field={@action_form[:image_pull]}
                id={@id <> "recreate_pull_image_value"}
              />
              <.action_button
                label="Recreate"
                icon="hero-arrow-path-rounded-square"
                disabled={not Policy.recreatable?(@container_name, @core)}
                tone="accent"
              />
            </.form>

            <.form
              for={@action_form}
              id={@id <> "recreate-options-form"}
              phx-change="change_recreate_options"
              phx-target={@myself}
              class="pr-2 font-mono text-xs text-mid-visibility"
            >
              <.input
                id={@id <> "recreate_pull_image"}
                field={@action_form[:image_pull]}
                type="checkbox"
                label="Pull first"
                bg_color="bg-primary-lighter"
                custom_classes="container-manager-pull-checkbox"
              />
            </.form>
          </div>

          <.form for={@action_form} id={@id <> "pull-form"} phx-submit="image-pull">
            <.input
              type="hidden"
              field={@action_form[:node]}
              id={@id <> "pull_nodename"}
              value={@nodename}
            />
            <.input
              type="hidden"
              field={@action_form[:image_tag]}
              id={@id <> "pull_image_tag"}
              value={@core.image_tag}
            />
            <.action_button label="Pull image" icon="hero-arrow-down-tray" />
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
