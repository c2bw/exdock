defmodule ExdockWeb.ReleasesLive.Index do
  @moduledoc """
  LiveView for repository release monitoring.

  Release data is fetched by local jobs and broadcast back into this page so
  users can compare configured repositories with available upstream versions.
  """

  use ExdockWeb, :live_view

  use ExdockWeb.PageLive.LivePage.Use,
    title: "Releases",
    load: [:repositories]

  alias Exdock.{Operations, ReadModel}
  alias Exdock.ReadModel.Repository
  alias ExdockWeb.PageLive.Utils.{EventParams, LiveOperation}
  alias ExdockWeb.PageLive.Utils.IdUtils
  alias ExdockWeb.PageLive.Utils.URLParam

  def bootstrap_page(params, _session, socket, %{repositories: repositories}) do
    socket
    |> setup_socket(Map.get(params, "repository_url", ""), repositories)
    |> assign_repository_data(repositories)
  end

  @spec setup_socket(Phoenix.Socket.t(), String.t(), [Repository.t()]) :: Phoenix.Socket.t()
  defp setup_socket(socket, encoded_repo_url, repositories) when is_list(repositories) do
    encoded_repo_url
    |> URLParam.decode()
    |> case do
      {:invalid, _} ->
        socket
        |> put_flash(:error, "Invalid repository parameter.")
        |> push_navigate(to: "/releases")

      {:ok, ""} ->
        socket

      {:ok, url} ->
        # Check if the repository URL is in the repository catalog.
        Enum.find(repositories, fn %Repository{url: repo_url} -> repo_url == url end)
        |> case do
          nil ->
            # Add flash and redirect to releases page
            socket
            |> put_flash(:warning, "Found no releases for repository #{url}.")
            |> push_navigate(to: "/releases")

          _ ->
            assign(socket, page_repository_url: url)
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.operational_page
      id="releases-index"
      content_id="releases-live-page"
      content_width={:compact}
      context={ExdockWeb.PageLive.LivePage.shell_context(assigns)}
    >
      <:aside>
        <ExdockWeb.ReleasesLive.AsideUserInput.render id="aside-user-input" />
        <ExdockWeb.ReleasesLive.AsideInfo.render
          id="aside-releases-info"
          modals_to_render={@modals_to_render}
          releases_page_count={@repository_overview.page_counts}
          log={@log}
        />
      </:aside>

      <div class="text-high-visibility h-full overflow-y-auto mb-48">
        <%= if assigns[:page_repository_url] do %>
          <ExdockWeb.ReleasesLive.List.render
            id="releases-list"
            repository_url={@page_repository_url}
            page_data={@page_repository_data}
            clock_now={@page_clock_now}
          />
        <% else %>
          <section
            id="releases-overview-header"
            class="mb-4 flex items-center justify-between gap-6 rounded-xl border border-secondary bg-primary-lighter px-5 py-4 shadow-sm"
            aria-labelledby="releases-overview-title"
          >
            <div class="flex min-w-0 items-center gap-3">
              <span class="grid size-10 shrink-0 place-items-center rounded-xl border border-[var(--accent)]/30 bg-[var(--accent-soft)] text-eye">
                <.icon name="hero-rocket-launch" class="size-5" />
              </span>

              <div class="min-w-0">
                <h1 id="releases-overview-title" class="text-lg font-semibold tracking-tight text-high-visibility">
                  Release monitoring
                </h1>

                <p class="text-xs text-low-visibility">Latest upstream versions across tracked repositories</p>
              </div>
            </div>

            <div class="flex shrink-0 items-center gap-2 font-mono text-xs">
              <button
                id="releases-sources-button"
                type="button"
                phx-click={show_modal("repositories_manager")}
                aria-haspopup="dialog"
                aria-controls="repositories_manager"
                title="Manage repositories"
                class="group rounded-lg border border-secondary bg-primary px-3 py-2 text-center transition duration-200 hover:-translate-y-0.5 hover:border-[var(--accent)] hover:bg-[var(--accent-soft)] hover:shadow-[inset_0_0_0_1px_var(--accent)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)]"
              >
                <span class="flex items-center gap-1 text-[0.625rem] uppercase tracking-wider text-low-visibility transition-colors group-hover:text-high-visibility">
                  Sources
                  <.icon
                    name="hero-chevron-right"
                    class="size-2.5 transition-transform group-hover:translate-x-0.5"
                  />
                </span>

                <span class="mt-0.5 block font-bold text-high-visibility">{length(@repositories)}</span>
              </button>

              <div class="rounded-lg border border-[var(--accent)]/30 bg-[var(--accent-soft)] px-3 py-2 text-center">
                <span class="text-[0.625rem] uppercase tracking-wider text-low-visibility">Releases</span>

                <span class="mt-0.5 block font-bold text-eye">
                  {@repository_overview.total_release_count}
                </span>
              </div>
            </div>
          </section>

          <.modal id="repositories_manager" max_width="max-w-[52rem]">
            <ExdockWeb.ReleasesLive.Manager.render
              id="repositories_manager-component"
              modal_id="repositories_manager"
              repositories={@repositories}
              clock_now={@page_clock_now}
            />
          </.modal>

          <div id="release-preview-list" class="grid grid-cols-1 gap-3 2xl:grid-cols-2">
            <%= for {page, release, count} <- @repository_overview.previews do %>
              <ExdockWeb.ReleasesLive.ReleasePreview.render
                id={IdUtils.create_id("#{release.repository}_preview")}
                page={page}
                release={release}
                count={count}
                clock_now={@page_clock_now}
              />
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.operational_page>
    """
  end

  def handle_page_broadcast({:repositories, repositories}, socket) when is_list(repositories),
    do: assign_repository_data(socket, repositories)

  def handle_page_broadcast(_message, _socket), do: :unhandled

  # Handle page specific events
  def handle_page_event("repository_releases_fetch", params, socket) do
    case EventParams.repository(params) do
      {:ok, repository} ->
        LiveOperation.handle(socket, Operations.fetch_repositories([repository]))

      {:error, :invalid_repository} ->
        LiveOperation.invalid(socket, "Invalid releases fetch request")
    end
  end

  def handle_page_event("releases_fetch_all", _params, socket) do
    LiveOperation.handle(socket, Operations.fetch_releases())
  end

  def handle_page_event(_event, _params, _socket), do: :unhandled

  defp assign_repository_data(socket, repositories) when is_list(repositories) do
    selected_url = Map.get(socket.assigns, :page_repository_url)

    assign(socket,
      repositories: repositories,
      repository_overview: ReadModel.repository_overview(repositories),
      page_repository_data: selected_repository(repositories, selected_url)
    )
  end

  defp selected_repository(_repositories, nil), do: nil

  defp selected_repository(repositories, selected_url),
    do: ReadModel.repository_data(repositories, selected_url)
end
