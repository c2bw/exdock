defmodule ExdockWeb.ReleasesLive.List do
  use ExdockWeb, :html

  alias Exdock.Datetime
  alias ExdockWeb.ReleasesLive

  attr :id, :string, required: true
  attr :repository_url, :string, required: true
  attr :page_data, :map, required: true
  attr :clock_now, :any, required: true

  def render(assigns) do
    releases = order_releases(assigns.page_data.releases)

    assigns =
      assign(assigns,
        ordered_releases: releases,
        release_count: length(releases)
      )

    ~H"""
    <div id="repository-release-history" class="flex flex-col gap-3">
      <section
        id="release-history-header"
        class="flex items-center justify-between gap-5 rounded-xl border border-secondary bg-primary-lighter px-5 py-4 shadow-sm"
        aria-labelledby="release-history-title"
      >
        <div class="flex min-w-0 items-center gap-3">
          <.link
            navigate="/releases"
            class="grid size-9 shrink-0 place-items-center rounded-lg border border-secondary bg-primary text-mid-visibility transition hover:border-[var(--accent)] hover:text-eye"
            aria-label="Back to release overview"
          >
            <.icon name="hero-arrow-left" class="size-4" />
          </.link>

          <div class="min-w-0">
            <div id="release-history-title">
              <ReleasesLive.ReleasePreview.repository_header
                provider_icon={@page_data.provider_icon}
                repository_label={@page_data.label}
              />
            </div>

            <p class="mt-1 font-mono text-[0.6875rem] text-low-visibility">
              {@release_count} releases <span class="mx-1 text-[var(--line-strong)]">•</span> newest first
            </p>
          </div>
        </div>
        <ReleasesLive.ReleasePreview.page_info
          page={@page_data.page}
          repository={@repository_url}
          clock_now={@clock_now}
        />
      </section>

      <section class="overflow-hidden rounded-xl border border-secondary bg-primary-lighter shadow-sm" aria-label="Release history">
        <div class="flex items-center justify-between border-b border-secondary px-4 py-2.5">
          <div class="flex items-center gap-2">
            <.icon name="hero-clock" class="size-4 text-eye" />
            <h2 class="font-mono text-xs font-semibold text-high-visibility">Version timeline</h2>
          </div>
          <span class="font-mono text-[0.625rem] uppercase tracking-wider text-low-visibility">Published</span>
        </div>

        <div id="release-history-items" class="first-divider-subtle divide-y divide-primary">
          <%= for {release, index} <- Enum.with_index(@ordered_releases) do %>
            <article
              id={ExdockWeb.PageLive.Utils.IdUtils.create_id("#{release.repository}_#{release.version}_history_item")}
              data-role="release-history-item"
              class="relative px-4 py-3 transition-colors hover:bg-secondary"
            >
              <div class="flex items-center gap-3">
                <span class={[
                  "grid size-8 shrink-0 place-items-center rounded-lg border",
                  if(index == 0,
                    do: "border-[var(--accent)]/35 bg-[var(--accent-soft)] text-eye",
                    else: "border-secondary bg-primary text-low-visibility"
                  )
                ]}>
                  <.icon name={if(index == 0, do: "hero-sparkles", else: "hero-tag")} class="size-3.5" />
                </span>

                <div class="min-w-0 flex-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <a
                      href={release.release_url}
                      target="_blank"
                      rel="noreferrer"
                      class="inline-flex min-w-0 items-center gap-1.5 font-mono text-sm font-bold text-high-visibility transition hover:text-eye"
                    >
                      <span class="truncate">{release.version}</span>
                      <.icon name="hero-arrow-up-right" class="size-3.5 shrink-0 text-low-visibility" />
                    </a>

                    <span
                      :if={index == 0}
                      class="rounded-md border border-[var(--accent)]/30 bg-[var(--accent-soft)] px-1.5 py-0.5 font-mono text-[0.625rem] font-bold uppercase tracking-wide text-eye"
                    >
                      Latest
                    </span>
                  </div>

                  <div class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 font-mono text-[0.625rem] text-low-visibility">
                    <span class="inline-flex items-center gap-1">
                      <.icon name="hero-clock" class="size-3" /> {release.time_released
                      |> Datetime.utc_to_timezone()
                      |> Datetime.simple_diff(@clock_now)} ago
                    </span>

                    <time datetime={DateTime.to_iso8601(release.time_released)}>
                      {release.time_released |> Datetime.utc_to_timezone() |> Datetime.prettify()}
                    </time>
                  </div>
                </div>
              </div>

              <%= if release.html_description != "" do %>
                <ReleasesLive.ReleasePreview.description
                  repository={release.repository}
                  id_source={"#{release.repository}_#{release.version}"}
                  html_description={release.html_description}
                />
              <% end %>
            </article>
          <% end %>
        </div>
      </section>
    </div>
    """
  end

  defp order_releases(releases), do: Enum.sort_by(releases, & &1.time_released, {:desc, DateTime})
end
