defmodule ExdockWeb.Commons.ContainerManager.Releases do
  alias Exdock.Operations
  use ExdockWeb, :live_component
  alias Exdock.Datetime
  alias ExdockWeb.PageLive.Utils.LiveOperation
  alias ExdockWeb.ReleasesLive

  @impl true
  def update(assigns, socket) do
    socket = assign_new(socket, :show_all_releases, fn -> false end)
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id <> "-panel"} aria-labelledby={@id <> "-heading"} class="pb-1">
      <div class="flex flex-col gap-3 border-b border-primary pb-4 sm:flex-row sm:items-center sm:justify-between">
        <div class="flex items-center gap-3">
          <span class="grid h-9 w-9 shrink-0 place-items-center rounded-lg border border-secondary bg-primary-lighter text-mid-visibility">
            <.icon name="hero-tag" class="h-4 w-4" />
          </span>

          <div>
            <div class="flex items-center gap-2">
              <h2 id={@id <> "-heading"} class="font-mono text-sm font-semibold text-high-visibility">
                Releases
              </h2>

              <span class="rounded-full border border-secondary bg-primary-lighter px-2 py-0.5 font-mono text-[0.675rem] font-semibold text-mid-visibility">
                {length(@releases)}
              </span>
            </div>

            <p class="mt-0.5 text-xs text-low-visibility">Latest project versions and release notes</p>
          </div>
        </div>

        <div class="flex items-center gap-2 self-start sm:self-auto">
          <div class="group flex items-center gap-2 rounded-lg border border-secondary bg-primary-lighter px-3 py-2">
            <.icon
              name={ReleasesLive.AsideInfo.page_state_to_icon(@page.state)}
              class={["h-4 w-4 shrink-0", ReleasesLive.AsideInfo.page_state_to_color(@page.state)]}
            />
            <%= if @page.last_check do %>
              <p class="w-36 whitespace-nowrap text-center font-mono text-[0.675rem] font-medium text-low-visibility group-hover:hidden">
                {@page.last_check |> Datetime.utc_to_timezone() |> Datetime.prettify()}
              </p>

              <p class="hidden w-36 whitespace-nowrap text-center font-mono text-[0.675rem] font-medium text-mid-visibility group-hover:block">
                {@page.last_check
                |> Datetime.utc_to_timezone()
                |> Datetime.elapsed_since(@clock_now)}
              </p>
            <% else %>
              <p class="w-36 text-center font-mono text-[0.675rem] font-medium text-low-visibility">Not checked</p>
            <% end %>
          </div>

          <button
            id={@id <> "-refresh"}
            type="button"
            aria-label="Refresh releases"
            title="Refresh releases"
            class="group grid h-9 w-9 place-items-center rounded-lg border border-secondary bg-primary-lighter text-mid-visibility shadow-sm transition hover:-translate-y-px hover:border-[var(--accent)] hover:bg-secondary hover:text-eye hover:shadow-md active:translate-y-0"
            phx-click="repository_releases_fetch"
            phx-value-repository={@repository_url}
            phx-target={@myself}
          >
            <.icon name="hero-arrow-path" class="h-4 w-4 transition-transform duration-500 group-hover:rotate-180" />
          </button>
        </div>
      </div>

      <div class="space-y-3 pt-4">
        <%= for release <- if @show_all_releases || false, do: @releases, else: Enum.take(@releases, 1) do %>
          <.card release={release} clock_now={@clock_now} />
        <% end %>
      </div>

      <%= if @releases |> Enum.count() > 0 and (not (@show_all_releases || false)) do %>
        <div class="mt-4 flex justify-center">
          <button
            id={@id <> "-show-all"}
            type="button"
            class="group inline-flex h-9 items-center justify-center gap-2 rounded-lg border border-secondary bg-primary-lighter px-4 text-xs font-semibold text-mid-visibility transition hover:border-primary hover:bg-secondary hover:text-high-visibility"
            phx-click="show_all_releases"
            phx-target={@myself}
          >
            Show all releases <.icon name="hero-chevron-down" class="h-4 w-4 transition-transform group-hover:translate-y-0.5" />
          </button>
        </div>
      <% end %>
    </section>
    """
  end

  defp card(assigns) do
    ~H"""
    <article class="overflow-hidden rounded-xl border border-secondary bg-primary-lighter shadow-sm transition hover:border-primary hover:shadow-md">
      <a
        href={@release.release_url}
        target="_blank"
        rel="noopener noreferrer"
        class="group flex w-full items-center justify-between gap-4 border-b border-secondary bg-primary px-4 py-3 transition hover:bg-secondary"
      >
        <div class="flex min-w-0 items-center gap-3">
          <span class="grid h-8 w-8 shrink-0 place-items-center rounded-lg border border-secondary bg-primary-lighter text-eye">
            <.icon name="hero-tag" class="h-4 w-4" />
          </span>

          <div class="min-w-0">
            <p class="text-[0.625rem] font-semibold uppercase tracking-[0.16em] text-low-visibility">Version</p>

            <p class="truncate font-mono text-sm font-semibold text-high-visibility transition group-hover:text-eye">
              {@release.version}
            </p>
          </div>
        </div>

        <div class="group/date first-divider-subtle-x flex shrink-0 items-center gap-3 font-mono text-[0.675rem] text-low-visibility">
          <span class="w-36 pr-3 text-right group-hover/date:hidden">
            {@release.time_released
            |> Datetime.utc_to_timezone()
            |> Datetime.simple_diff(@clock_now)}
          </span>

          <span class="hidden w-36 pr-3 text-right text-mid-visibility group-hover/date:block">
            {@release.time_released |> Datetime.utc_to_timezone() |> Datetime.prettify()}
          </span>

          <.icon
            name="hero-arrow-up-right"
            class="h-4 w-4 transition group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-eye"
          />
        </div>
      </a>

      <div class="bg-above-primary px-4 py-4 sm:px-5">
        <div class="release-markdown w-full max-w-none" data-role="release-markdown">
          {@release.html_description |> raw()}
        </div>
      </div>
    </article>
    """
  end

  @impl true
  def handle_event("repository_releases_fetch", params, socket) do
    case ExdockWeb.PageLive.Utils.EventParams.repository(params) do
      {:ok, repository} ->
        {:noreply, LiveOperation.handle_component(socket, Operations.fetch_repositories([repository]))}

      {:error, :invalid_repository} ->
        {:noreply, LiveOperation.invalid_component(socket, "Invalid releases fetch request")}
    end
  end

  def handle_event("show_all_releases", _, socket) do
    {:noreply, assign(socket, :show_all_releases, true)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, LiveOperation.invalid_component(socket)}
end
