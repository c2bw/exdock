defmodule ExdockWeb.Commons.ContainerManager.Header do
  use ExdockWeb, :html

  alias Exdock.Datetime
  alias ExdockWeb.ContainerPolicyControls

  attr :id, :string, required: true
  attr :nodename, :any, required: true
  attr :container_name, :string, required: true
  attr :core, :map, required: true
  attr :target, :any, required: true

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :fetch_staleness,
        Datetime.elapsed_to_staleness(assigns.core.fetched_at)
      )

    ~H"""
    <header id={@id <> "-identity"} class="pr-10">
      <div class="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
        <div class="min-w-0">
          <div class="flex items-center gap-3">
            <span class={[
              "relative flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border shadow-sm",
              @core.is_running && "border-emerald-500/30 bg-emerald-500/10 text-success",
              !@core.is_running && "border-primary bg-secondary text-low-visibility"
            ]}>
              <.icon name="hero-cube" class="h-6 w-6" />
              <span class={[
                "absolute -bottom-0.5 -right-0.5 h-3 w-3 rounded-full border-2 border-[var(--surface-base)]",
                @core.is_running && "bg-emerald-500",
                !@core.is_running && "bg-stone-500"
              ]} />
            </span>

            <div class="min-w-0">
              <p class="mb-0.5 text-[0.625rem] font-semibold uppercase tracking-[0.16em] text-low-visibility">
                Container Manager
              </p>

              <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
                <h1 id={@id <> "-title"} class="truncate text-xl font-semibold tracking-tight text-high-visibility">
                  {@container_name}
                </h1>

                <span class={[
                  "rounded-full border px-2 py-0.5 text-[0.675rem] font-semibold uppercase tracking-wider",
                  @core.is_running && "border-emerald-500/30 bg-emerald-500/10 text-success",
                  !@core.is_running && "border-primary bg-secondary text-low-visibility"
                ]}>
                  {if(@core.is_running, do: "Running", else: "Stopped")}
                </span>
              </div>

              <p class="mt-0.5 flex items-center gap-1.5 text-xs text-low-visibility">
                <.icon name="hero-server-stack" class="h-3.5 w-3.5" /> <span class="truncate font-mono">{@nodename}</span>
              </p>
            </div>
          </div>

          <div class="mt-3 flex flex-wrap items-center gap-2 text-xs text-low-visibility">
            <span class="inline-flex items-center gap-1.5 rounded-md border border-secondary bg-primary-lighter px-2 py-1">
              <%= case @fetch_staleness do %>
                <% :fresh -> %>
                  <.icon name="hero-clock" class="h-3.5 w-3.5 text-success" />
                <% :stale -> %>
                  <.icon name="hero-clock" class="h-3.5 w-3.5 text-warning" />
                <% :old -> %>
                  <.icon name="hero-clock" class="h-3.5 w-3.5 text-amber-600" />
                <% nil -> %>
                  <.icon name="hero-clock" class="h-3.5 w-3.5" />
              <% end %>
              Updated {@core.fetched_at |> Datetime.utc_to_timezone() |> Datetime.prettify()}
            </span>

            <button
              id={@id <> "-refresh"}
              type="button"
              phx-click="node_refresh"
              phx-value-nodename={@nodename}
              class="group inline-flex items-center gap-1.5 rounded-md border border-secondary bg-primary-lighter px-2 py-1 font-medium text-mid-visibility transition hover:border-primary hover:text-high-visibility"
            >
              <.icon name="hero-arrow-path" class="h-3.5 w-3.5 transition-transform duration-300 group-hover:rotate-90" /> Refresh
            </button>

            <a
              href={@core.repository_url}
              target="_blank"
              rel="noreferrer"
              class="inline-flex items-center gap-1.5 rounded-md border border-secondary bg-primary-lighter px-2 py-1 font-medium text-mid-visibility transition hover:border-primary hover:text-high-visibility"
            >
              Repository <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" />
            </a>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-2 sm:flex sm:items-stretch">
          <div class="group w-full rounded-xl border border-primary bg-primary-lighter p-2.5 shadow-sm transition-colors hover:border-[var(--accent)] sm:w-44 sm:flex-none">
            <p class="mb-1.5 text-center text-[0.625rem] font-semibold uppercase tracking-wider text-low-visibility">Auto update</p>

            <ContainerPolicyControls.auto_update_stepper
              id={@id <> "-auto-update"}
              node={@nodename}
              container={@container_name}
              current_policy={@core.settings.auto_update}
              target={@target}
              variant={:compact}
            />
          </div>

          <div class="group w-full rounded-xl border border-primary bg-primary-lighter p-2.5 shadow-sm transition-colors hover:border-[var(--accent)] sm:w-32 sm:flex-none">
            <p class="mb-1.5 text-center text-[0.625rem] font-semibold uppercase tracking-wider text-low-visibility">Priority</p>

            <ContainerPolicyControls.priority_stepper
              id={@id <> "-priority"}
              node={@nodename}
              container={@container_name}
              priority={@core.settings.priority}
              target={@target}
              variant={:compact}
            />
          </div>
        </div>
      </div>
    </header>
    """
  end
end
