defmodule ExdockWeb.PageLive.AsideFooter do
  @moduledoc """
  Footer content for the shared sidebar.

  Keeps secondary navigation and global actions visually consistent across the
  LiveView pages that embed `AsideComponent`.
  """

  use ExdockWeb, :html

  def render(assigns) do
    ~H"""
    <footer
      id="sidebar-footer"
      class="sidebar-card mt-2 flex shrink-0 items-center gap-1.5 overflow-hidden p-1.5"
    >
      <span class="grid size-7 shrink-0 place-items-center rounded-md border border-secondary bg-secondary text-eye">
        <.icon name="hero-cube-transparent" class="size-3.5" />
      </span>

      <div class="min-w-0 flex-1">
        <p class="truncate font-mono text-xs font-bold tracking-wide text-high-visibility">Exdock</p>
      </div>

      <span class="shrink-0 rounded-md border border-secondary bg-primary px-1.5 py-1 font-mono text-[0.625rem] font-bold tabular-nums text-eye">
        v{Application.spec(:exdock, :vsn)}
      </span>

      <nav class="flex shrink-0 items-center gap-1" aria-label="Exdock resources">
        <button
          id="sidebar-about-button"
          type="button"
          class="control-lift-action sidebar-footer-action sidebar-footer-action--compact"
          phx-click={show_modal("about-page")}
          title="About Exdock"
          aria-label="About Exdock"
        >
          <.icon name="hero-information-circle" class="size-4" />
          <span class="sr-only">About</span>
        </button>

        <a
          id="sidebar-github-link"
          href="https://github.com/c2bw/exdock"
          class="control-lift-action sidebar-footer-action sidebar-footer-action--compact"
          target="_blank"
          rel="noreferrer"
          title="View Exdock on GitHub"
          aria-label="View Exdock on GitHub"
        >
          <img src={~p"/images/github-mark.svg"} width="14" height="14" alt="" />
          <span class="sr-only">GitHub</span>
        </a>
      </nav>
    </footer>
    """
  end
end
