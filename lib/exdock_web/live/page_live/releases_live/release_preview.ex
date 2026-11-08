defmodule ExdockWeb.ReleasesLive.ReleasePreview do
  use ExdockWeb, :html
  alias ExdockWeb.ReleasesLive
  alias ExdockWeb.PageLive.Utils.IdUtils
  alias ExdockWeb.PageLive.Utils.URLParam
  alias Exdock.Datetime

  attr :id, :string, required: true
  attr :page, :map, required: true
  attr :release, :map, required: true
  attr :count, :integer, required: true
  attr :clock_now, :any, required: true

  def render(assigns) do
    ~H"""
    <article class="group flex flex-col rounded-xl border border-secondary bg-primary-lighter p-4 shadow-sm transition duration-150 hover:border-[var(--line-default)] hover:shadow-md">
      <div class="flex w-full items-start gap-4">
        <.release_info release={@release} clock_now={@clock_now} />
        <div class="flex shrink-0 flex-col items-end gap-2">
          <.page_info page={@page} repository={@release.repository} clock_now={@clock_now} />
        </div>
      </div>

      <%= if @release.html_description != "" do %>
        <.description repository={@release.repository} html_description={@release.html_description} />
      <% end %>

      <div class="mt-3 flex items-center justify-between border-t border-secondary pt-3">
        <span class="font-mono text-[0.625rem] uppercase tracking-wider text-low-visibility">Release history</span>
        <.link
          navigate={"/releases/#{URLParam.encode(@release.repository)}"}
          class="inline-flex items-center gap-1.5 rounded-lg border border-secondary bg-primary px-2.5 py-1.5 font-mono text-xs font-semibold text-mid-visibility transition hover:border-[var(--accent)] hover:text-eye"
        >
          <span>{@count} releases</span>
          <.icon name="hero-arrow-right" class="size-3.5 transition-transform group-hover:translate-x-0.5" />
        </.link>
      </div>
    </article>
    """
  end

  attr :release, :map, required: true
  attr :hide_header, :boolean, default: false
  attr :clock_now, :any, required: true

  def release_info(assigns) do
    ~H"""
    <div class="min-w-0 flex-1">
      <a href={@release.release_url} target="_blank" rel="noreferrer" class="group/release block min-w-0">
        <%= if not (assigns[:hide_header] || false) do %>
          <.repository_header
            provider_icon={@release.provider_icon}
            repository_label={@release.repository_label}
          />
        <% end %>

        <div class="mt-2 flex flex-wrap items-center gap-2 font-mono">
          <span class="inline-flex items-center gap-1 rounded-md border border-[var(--accent)]/25 bg-[var(--accent-soft)] px-2 py-1 text-xs font-bold text-eye">
            <.icon name="hero-tag" class="size-3" /> {@release.version}
          </span>

          <span class="inline-flex items-center gap-1 text-[0.6875rem] font-semibold text-low-visibility">
            <.icon name="hero-clock" class="size-3.5" /> {@release.time_released
            |> Datetime.utc_to_timezone()
            |> Datetime.simple_diff(@clock_now)} ago
          </span>
          <.icon name="hero-arrow-up-right" class="size-3.5 text-low-visibility transition group-hover/release:text-eye" />
        </div>
      </a>
    </div>
    """
  end

  attr :provider_icon, :string, required: true
  attr :repository_label, :string, required: true

  def repository_header(assigns) do
    ~H"""
    <div class="flex min-w-0 items-center gap-2.5">
      <span class="grid size-8 shrink-0 place-items-center rounded-lg border border-secondary bg-primary">
        <%= if @provider_icon do %>
          <img src={"/images/#{@provider_icon}"} width="16" height="16" alt="" />
        <% else %>
          <.icon name="hero-code-bracket" class="size-4 text-mid-visibility" />
        <% end %>
      </span>

      <p class="truncate font-mono text-sm font-bold text-high-visibility transition group-hover/release:text-eye">
        {@repository_label}
      </p>
    </div>
    """
  end

  attr :page, :map, required: true
  attr :repository, :string, required: true
  attr :clock_now, :any, required: true

  def page_info(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="inline-flex items-center gap-1.5 rounded-md border border-secondary bg-primary px-2 py-1 font-mono text-[0.625rem] font-semibold text-mid-visibility">
        <.icon
          name={ReleasesLive.AsideInfo.page_state_to_icon(@page.state)}
          class={["size-3.5", ReleasesLive.AsideInfo.page_state_to_color(@page.state)]}
        /> {page_state_label(@page.state)}
      </span>

      <div class="group/check text-right">
        <%= if @page.last_check do %>
          <time
            data-role="repository-last-fetched"
            datetime={DateTime.to_iso8601(@page.last_check)}
            class="block text-[0.625rem] font-mono font-semibold text-low-visibility group-hover/check:hidden"
          >
            {@page.last_check |> Datetime.utc_to_timezone() |> Datetime.prettify()}
          </time>

          <time
            data-role="repository-last-fetched-relative"
            datetime={DateTime.to_iso8601(@page.last_check)}
            class="hidden text-[0.625rem] font-mono font-semibold text-low-visibility group-hover/check:block"
          >
            fetched {@page.last_check
            |> Datetime.utc_to_timezone()
            |> Datetime.elapsed_since(@clock_now)} ago
          </time>
        <% else %>
          <p class="text-[0.625rem] font-mono font-semibold text-low-visibility">Not checked</p>
        <% end %>
      </div>

      <button
        type="button"
        class="grid size-8 place-items-center rounded-lg border border-secondary bg-primary text-mid-visibility transition hover:border-[var(--accent)] hover:text-eye"
        phx-click="repository_releases_fetch"
        phx-value-repository={@repository}
        aria-label={"Refresh #{@repository} releases"}
      >
        <.icon name="hero-arrow-path" class="size-4 transition-transform duration-500 hover:rotate-90" />
      </button>
    </div>
    """
  end

  attr :repository, :string, required: true
  attr :html_description, :string, required: true
  attr :id_source, :string

  def description(assigns) do
    assigns = assign_new(assigns, :id_source, fn -> assigns.repository end)

    ~H"""
    <div class="mt-3">
      <details
        class="group/notes overflow-hidden rounded-lg border border-secondary bg-primary"
        id={IdUtils.create_id("#{@id_source}_details")}
        phx-hook="CollapsibleState"
      >
        <summary
          class="flex min-h-9 cursor-pointer list-none items-center justify-between gap-3 px-3 text-mid-visibility transition hover:bg-secondary hover:text-high-visibility"
          id={IdUtils.create_id("#{@id_source}_details_summary")}
        >
          <span class="inline-flex items-center gap-2 font-mono text-xs font-semibold">
            <.icon name="hero-document-text" class="size-3.5 text-eye" /> Release notes
          </span>
          <.icon name="hero-chevron-down" class="size-4 transition-transform group-open/notes:rotate-180" />
        </summary>

        <div class="flex w-full justify-start border-t border-secondary px-4">
          <article
            class={["release-markdown", "mt-2 mb-2 w-full max-w-7xl max-h-full"]}
            data-role="release-markdown"
          >
            {@html_description |> raw()}
          </article>
        </div>
      </details>
    </div>
    """
  end

  defp page_state_label(:ok), do: "Synced"
  defp page_state_label(:unknown), do: "Pending"
  defp page_state_label(:not_found), do: "Not found"
  defp page_state_label(:rate_limit), do: "Rate limited"
  defp page_state_label(:unsupported), do: "Unsupported"
  defp page_state_label(:error), do: "Error"
end
