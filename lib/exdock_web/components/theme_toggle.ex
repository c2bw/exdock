defmodule ExdockWeb.Components.ToggleTheme do
  @moduledoc "Theme switcher shared by public and authenticated pages."

  use ExdockWeb, :html

  def render(assigns) do
    ~H"""
    <div
      id="theme-toggle"
      phx-update="ignore"
      phx-hook="DarkThemeToggle"
      class="theme-toggle"
      role="group"
      aria-label="Color theme"
      data-theme-preference="system"
    >
      <span class="theme-toggle__indicator" aria-hidden="true"></span>

      <button
        id="theme-system"
        type="button"
        class="theme-toggle__option"
        data-theme-option="system"
        aria-label="Use system theme"
        aria-pressed="true"
        title="System theme"
      >
        <.icon name="hero-computer-desktop" class="h-3.5 w-3.5" />
      </button>

      <button
        id="theme-light"
        type="button"
        class="theme-toggle__option"
        data-theme-option="light"
        aria-label="Use light theme"
        aria-pressed="false"
        title="Light theme"
      >
        <.icon name="hero-sun" class="h-3.5 w-3.5" />
      </button>

      <button
        id="theme-dark"
        type="button"
        class="theme-toggle__option"
        data-theme-option="dark"
        aria-label="Use dark theme"
        aria-pressed="false"
        title="Dark theme"
      >
        <.icon name="hero-moon" class="h-3.5 w-3.5" />
      </button>
    </div>
    """
  end
end
