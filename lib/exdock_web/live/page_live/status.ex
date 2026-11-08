defmodule ExdockWeb.PageLive.Status do
  @moduledoc """
  Shared job/status strip shown at the top of operational pages.

  Status data is supplied by server logging broadcasts; this component focuses
  on rendering active, finished, and failed job states consistently.
  """

  use ExdockWeb, :html
  alias Exdock.ReadModel.Status

  attr :id, :string, required: true
  attr :status, :map, required: true

  def render(assigns) do
    active_jobs = Status.active_job_count(assigns.status)
    has_errors = Status.errors?(assigns.status)

    assigns =
      assign(assigns,
        active_jobs: active_jobs,
        has_errors: has_errors,
        presentation: status_presentation(active_jobs, has_errors)
      )

    ~H"""
    <div
      id="cluster-status-bar"
      class="mb-4 rounded-xl border border-secondary bg-primary-lighter p-1.5 shadow-sm transition duration-150 hover:border-[var(--accent)] hover:shadow-[inset_0_0_0_1px_var(--accent)] focus-within:border-[var(--accent)] focus-within:shadow-[inset_0_0_0_1px_var(--accent)]"
      aria-live="polite"
    >
      <button
        id="cluster-status-button"
        type="button"
        class="flex min-h-12 w-full min-w-0 cursor-pointer items-center gap-3 rounded-lg px-3 text-left transition duration-150 hover:bg-secondary focus-visible:outline-none"
        phx-click={show_modal("status-component-modal")}
        aria-haspopup="dialog"
        aria-label="Open detailed system status"
        data-status={@presentation.state}
      >
        <span class={[
          "relative grid size-9 shrink-0 place-items-center rounded-lg border",
          @presentation.surface
        ]}>
          <.icon name={@presentation.icon} class="size-4" />
          <span
            :if={@active_jobs > 0}
            class={[
              "absolute -right-0.5 -top-0.5 size-2.5 rounded-full border-2 border-[var(--surface-raised)] motion-safe:animate-pulse",
              @presentation.indicator
            ]}
          />
        </span>

        <span class="flex min-w-24 shrink-0 flex-col">
          <span class="text-[0.65rem] font-semibold uppercase tracking-[0.16em] text-low-visibility">
            System status
          </span>
          <span class={["text-sm font-semibold", @presentation.text]}>{@presentation.label}</span>
        </span>
        <span class="h-7 w-px shrink-0 bg-[var(--line-subtle)]" aria-hidden="true" />
        <span class="flex min-w-0 flex-1 items-center gap-2 font-mono">
          <span class="shrink-0 text-xs font-semibold text-high-visibility">{@status.latest_job}</span>
          <.icon name="hero-arrow-right" class="size-3.5 shrink-0 text-low-visibility" />
          <span class={[
            "truncate text-xs",
            if(@status.latest_job_message_is_error, do: "text-error font-semibold", else: "text-mid-visibility")
          ]}>
            {@status.latest_job_message}
          </span>
        </span>

        <span class="hidden shrink-0 items-center gap-1.5 rounded-md border border-secondary bg-primary px-2 py-1 text-[0.65rem] font-semibold text-mid-visibility md:inline-flex">
          <span>{@active_jobs}</span> <span>{if(@active_jobs == 1, do: "active job", else: "active jobs")}</span>
        </span>
      </button>

      <.modal id="status-component-modal">
        <ExdockWeb.PageLive.StatusModal.render
          id="status-component-modal-lc"
          dash={@status.dash}
          has_errors={@has_errors}
          errors_log={@status.errors}
        />
      </.modal>
    </div>
    """
  end

  defp status_presentation(_active_jobs, true) do
    %{
      state: :attention,
      label: "Needs attention",
      icon: "hero-exclamation-triangle",
      surface: "border-red-500/30 bg-red-500/10 text-error",
      text: "text-error",
      indicator: "bg-red-500"
    }
  end

  defp status_presentation(active_jobs, false) when active_jobs > 0 do
    %{
      state: :working,
      label: "Working",
      icon: "hero-arrow-path",
      surface: "border-blue-500/40 bg-blue-500/15 text-blue-700 dark:text-blue-400",
      text: "text-blue-700 dark:text-blue-400",
      indicator: "bg-blue-500"
    }
  end

  defp status_presentation(_active_jobs, false) do
    %{
      state: :ready,
      label: "Ready",
      icon: "hero-check-circle",
      surface: "border-[var(--accent)]/25 bg-[var(--accent-soft)] text-eye",
      text: "text-high-visibility",
      indicator: "bg-[var(--accent)]"
    }
  end
end
