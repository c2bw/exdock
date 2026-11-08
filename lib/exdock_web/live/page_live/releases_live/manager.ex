defmodule ExdockWeb.ReleasesLive.Manager do
  use ExdockWeb, :html

  alias ExdockWeb.PageLive.Utils.IdUtils
  alias ExdockWeb.ReleasesLive
  alias ExdockWeb.ReleasesLive.Manager.RepositorySourceRow

  attr :id, :string, required: true
  attr :modal_id, :string, required: true
  attr :repositories, :list, required: true
  attr :clock_now, :any, required: true

  def render(assigns) do
    rows = RepositorySourceRow.build_all(assigns.repositories, assigns.clock_now)

    assigns =
      assigns
      |> assign(:repository_rows, rows)
      |> assign(:repository_count, length(rows))

    ~H"""
    <div id={@id} class="min-w-0">
      <header class="flex items-start gap-3 pr-10">
        <span class="grid size-11 shrink-0 place-items-center rounded-xl border border-[var(--accent)]/25 bg-[var(--accent-soft)] text-eye">
          <.icon name="hero-code-bracket-square" class="size-5" />
        </span>

        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h2 id={@modal_id <> "-title"} class="text-lg font-semibold tracking-tight text-high-visibility">
              Sources & releases
            </h2>

            <span class="rounded-full border border-secondary bg-primary px-2 py-0.5 font-mono text-[0.675rem] font-bold tabular-nums text-mid-visibility">
              {@repository_count}
            </span>
          </div>

          <p id={@modal_id <> "-description"} class="mt-1 max-w-2xl text-xs leading-5 text-low-visibility">
            Review tracked repositories, open their source pages, and refresh release information individually.
          </p>
        </div>
      </header>

      <section class="mt-5" aria-label="Repository sources">
        <div
          id="repositories-manager-list"
          class="h-[34rem] max-h-[70vh] space-y-0.5 overflow-y-auto rounded-xl border border-secondary bg-primary p-1"
        >
          <div
            :if={@repository_count == 0}
            id="repositories-manager-empty"
            class="flex h-full flex-col items-center justify-center px-5 text-center"
          >
            <span class="mx-auto grid size-10 place-items-center rounded-xl border border-secondary bg-secondary text-low-visibility">
              <.icon name="hero-link-slash" class="size-5" />
            </span>

            <p class="mt-3 text-sm font-semibold text-high-visibility">No sources tracked</p>
            <p class="mt-1 text-xs text-low-visibility">Repository sources appear here when they are linked to images.</p>
          </div>

          <%= for row <- @repository_rows do %>
            <article
              id={IdUtils.create_id("repository_source_#{row.url}")}
              data-role="repository-source"
              class="group flex items-center gap-2 rounded-lg border border-transparent bg-primary-lighter px-2 py-1.5 transition duration-150 hover:border-[var(--accent)] hover:shadow-[inset_0_0_0_1px_var(--accent)]"
            >
              <span class={[
                "grid size-7 shrink-0 place-items-center rounded-md border border-secondary bg-primary",
                ReleasesLive.AsideInfo.page_state_to_color(row.state)
              ]}>
                <.icon name={ReleasesLive.AsideInfo.page_state_to_icon(row.state)} class="size-3.5" />
              </span>

              <div class="min-w-0 flex-1">
                <a
                  href={row.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label={"Open repository #{row.url}"}
                  class="group/link inline-flex max-w-full items-start gap-1.5 break-all font-mono text-xs font-bold leading-4 text-high-visibility transition hover:text-eye focus-visible:rounded focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)]"
                >
                  <span>{row.url}</span>
                  <.icon
                    name="hero-arrow-up-right"
                    class="mt-px size-3 shrink-0 text-low-visibility transition group-hover/link:-translate-y-0.5 group-hover/link:translate-x-0.5 group-hover/link:text-eye"
                  />
                </a>

                <div class="mt-0.5 flex flex-wrap items-center gap-x-1.5 gap-y-0.5 font-mono text-[0.625rem] leading-3">
                  <span class={[
                    "inline-flex items-center gap-1 font-semibold",
                    ReleasesLive.AsideInfo.page_state_to_color(row.state)
                  ]}>
                    <span class="size-1.5 rounded-full bg-current"></span>
                    {row.state_label}
                  </span>

                  <span class="text-low-visibility" aria-hidden="true">•</span>
                  <span class="text-mid-visibility">{row.release_count_label}</span>
                  <span class="text-low-visibility" aria-hidden="true">•</span>
                  <time
                    datetime={row.last_check && DateTime.to_iso8601(row.last_check)}
                    title={row.last_check_title}
                    class="text-low-visibility"
                  >
                    {row.last_check_label}
                  </time>
                </div>
              </div>

              <button
                id={IdUtils.create_id("refresh_repository_#{row.url}")}
                type="button"
                phx-click="repository_releases_fetch"
                phx-value-repository={row.url}
                aria-label={"Refresh releases for #{row.url}"}
                title="Refresh releases"
                class="group/refresh grid size-7 shrink-0 place-items-center rounded-md border border-secondary bg-primary text-mid-visibility transition hover:border-[var(--accent)] hover:text-eye focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)]"
              >
                <.icon
                  name="hero-arrow-path"
                  class="size-3 transition-transform duration-500 group-hover/refresh:rotate-90"
                />
              </button>
            </article>
          <% end %>
        </div>
      </section>
    </div>
    """
  end
end
