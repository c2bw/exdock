defmodule ExdockWeb.Components.Navbar do
  @moduledoc """
  Top navigation shared by authenticated LiveView pages.

  The navbar is intentionally small and stateless: page-level LiveViews own the
  modals and navigation state, while this component only emits navigation links,
  lazy-modal events, the theme toggle, and session actions.
  """

  use ExdockWeb, :html

  attr :current_user, :any, default: nil

  @doc """
  Render the fixed application navigation bar.
  """
  def render(assigns) do
    ~H"""
    <header
      id="app-navbar"
      class="fixed inset-x-0 top-0 z-40 h-12 border-b border-primary bg-tertiary shadow-[0_1px_0_rgb(255_255_255/0.04)] backdrop-blur-xl"
    >
      <nav class="grid h-full grid-cols-[1fr_auto_1fr] items-center gap-3 px-3 sm:px-4" aria-label="Primary navigation">
        <div class="flex min-w-0 items-center gap-1 overflow-hidden">
          <%= if @current_user do %>
            <.text_lazy_modal text="Settings" icon="hero-adjustments-horizontal" modal_name="settings-page" />
            <.text_navigate text="Automation" icon="hero-calendar" navigate_to={~p"/automation"} />
            <.text_navigate text="Images" icon="hero-square-2-stack" navigate_to={~p"/images"} />
            <.text_navigate text="Releases" icon="hero-bars-3" navigate_to={~p"/releases"} />
          <% end %>
        </div>

        <.link
          navigate={~p"/"}
          class="group flex items-center gap-2 rounded-lg px-2 py-1 transition-colors bg-hover"
          aria-label="Exdock home"
        >
          <img src={~p"/images/exdock.svg"} width="30" height="30" alt="" />
          <span class="hidden font-mono text-sm font-bold tracking-tight text-high-visibility sm:inline">Exdock</span>
        </.link>

        <div class="flex min-w-0 items-center justify-end gap-2 sm:gap-3">
          <ExdockWeb.Components.ToggleTheme.render />

          <%= if @current_user do %>
            <ul class="flex min-w-0 items-center gap-2 sm:gap-3">
              <li class="hidden min-w-0 text-xs font-mono text-low-visibility md:block">
                <p class="max-w-24 truncate lg:max-w-40">{@current_user.email}</p>
              </li>

              <li>
                <.link
                  href={~p"/users/log_out"}
                  method="delete"
                  class="group flex items-center gap-1.5 rounded-lg px-2 py-1.5 font-mono text-xs font-semibold text-low-visibility transition-colors bg-hover text-hover-eye"
                >
                  <.icon name="hero-arrow-left-start-on-rectangle" class="h-4 w-4" />
                  <span class="hidden lg:inline">Log out</span>
                </.link>
              </li>
            </ul>
          <% end %>
        </div>
      </nav>
    </header>
    """
  end

  # Emits the shared "show_lazy_modal" event handled by CommonPageHandler. The
  # modal itself is rendered by the current page so expensive content can stay
  # unmounted until the user asks for it.
  defp text_lazy_modal(assigns) do
    ~H"""
    <button
      type="button"
      class="group rounded-lg px-2 py-1.5 font-mono text-xs font-semibold text-low-visibility transition-colors bg-hover text-hover-eye"
      phx-click={show_lazy_modal(@modal_name)}
      aria-label={@text}
    >
      <.text_and_icon text={@text} icon={@icon} />
    </button>
    """
  end

  # Navigation entries use LiveView navigation so page transitions do not force a
  # full browser reload.
  defp text_navigate(assigns) do
    ~H"""
    <.link
      navigate={@navigate_to}
      class="group rounded-lg px-2 py-1.5 font-mono text-xs font-semibold text-low-visibility transition-colors bg-hover text-hover-eye"
      aria-label={@text}
    >
      <.text_and_icon text={@text} icon={@icon} />
    </.link>
    """
  end

  defp text_and_icon(assigns) do
    ~H"""
    <span class="flex items-center gap-1.5 whitespace-nowrap">
      <.icon name={@icon} class="h-4 w-4 transition-transform group-hover:-translate-y-px" />
      <span class="hidden xl:inline">{@text}</span>
    </span>
    """
  end
end
