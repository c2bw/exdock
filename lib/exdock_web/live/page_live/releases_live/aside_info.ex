defmodule ExdockWeb.ReleasesLive.AsideInfo do
  use ExdockWeb, :html

  attr :id, :string, required: true
  attr :modals_to_render, :map, required: true
  attr :releases_page_count, :map, required: true
  attr :log, :list, required: true

  def render(assigns) do
    repositories_count = assigns.releases_page_count |> Map.values() |> Enum.sum()
    assigns = assign(assigns, :repositories_count, repositories_count)

    ~H"""
    <div class="flex flex-col flex-grow space-y-2 mt-4">
      <div class="flex flex-grow items-end"></div>
      <ExdockWeb.PageLive.Log.render id="aside-images-log" modals_to_render={@modals_to_render} log={@log} />
      <%= if @repositories_count > 0 do %>
        <section
          id="sidebar-repositories-summary"
          class="sidebar-card p-2"
          aria-labelledby="sidebar-repositories-title"
        >
          <div class="flex items-center justify-between px-1.5 pb-2 pt-1">
            <div class="flex min-w-0 items-center gap-2.5">
              <span class="control-icon-tile sidebar-icon-tile size-8">
                <.icon name="hero-code-bracket-square" class="size-4" />
              </span>

              <div class="min-w-0">
                <p id="sidebar-repositories-title" class="font-mono text-xs font-bold tracking-tight text-high-visibility">
                  Repositories
                </p>

                <p class="font-mono text-xxs text-low-visibility">Release sources</p>
              </div>
            </div>
            <span class="sidebar-count" aria-label={"#{@repositories_count} repositories total"}>{@repositories_count}</span>
          </div>

          <div class="space-y-1">
            <.page_state name="Ready" description="Releases available" page={:ok} count={@releases_page_count} />
            <.page_state name="Unknown" description="Awaiting status" page={:unknown} count={@releases_page_count} />
            <.page_state name="Not found" description="No releases page" page={:not_found} count={@releases_page_count} />
            <.page_state name="Rate limited" description="Provider throttled" page={:rate_limit} count={@releases_page_count} />
            <.page_state name="Unsupported" description="Provider unsupported" page={:unsupported} count={@releases_page_count} />
            <.page_state name="Error" description="Release fetch failed" page={:error} count={@releases_page_count} />
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  defp page_state(assigns) do
    assigns =
      assign(assigns,
        icon: page_state_to_icon(assigns.page),
        icon_color: page_state_to_color(assigns.page),
        surface: page_state_to_surface(assigns.page),
        state_count: Map.get(assigns.count, assigns.page, 0)
      )

    ~H"""
    <%= if @state_count > 0 do %>
      <div class="group flex min-h-12 items-center gap-2 rounded-lg border border-transparent px-2 py-1.5 transition-colors hover:border-secondary hover:bg-secondary">
        <span class={[
          "grid size-8 shrink-0 place-items-center rounded-lg border border-secondary transition-colors group-hover:border-[var(--line-default)]",
          @icon_color,
          @surface
        ]}>
          <.icon name={@icon} class="size-4" />
        </span>

        <div class="min-w-0 flex-1">
          <p class="truncate font-mono text-xs font-semibold text-high-visibility">{@name}</p>

          <p class="truncate font-mono text-[0.625rem] text-low-visibility">{@description}</p>
        </div>

        <span
          class={[
            "min-w-7 rounded-md border border-secondary bg-primary px-1.5 py-1 text-center font-mono text-xs font-bold tabular-nums",
            @icon_color
          ]}
          aria-label={"#{@state_count} repositories #{@name}"}
        >
          {@state_count}
        </span>
      </div>
    <% end %>
    """
  end

  def page_state_to_icon(:unknown), do: "hero-question-mark-circle"
  def page_state_to_icon(:ok), do: "hero-check-circle"
  def page_state_to_icon(:not_found), do: "hero-exclamation-circle"
  def page_state_to_icon(:rate_limit), do: "hero-shield-exclamation"
  def page_state_to_icon(:unsupported), do: "hero-x-circle"
  def page_state_to_icon(:error), do: "hero-exclamation-triangle"

  def page_state_to_color(:unknown), do: "text-container-unknown"
  def page_state_to_color(:ok), do: "text-container-updated"
  def page_state_to_color(:not_found), do: "text-container-unknown"
  def page_state_to_color(:rate_limit), do: "text-container-outdated"
  def page_state_to_color(:unsupported), do: "text-container-outdated"
  def page_state_to_color(:error), do: "text-container-errored"

  defp page_state_to_surface(:ok), do: "bg-[var(--accent-soft)]"
  defp page_state_to_surface(:unknown), do: "bg-slate-500/10"
  defp page_state_to_surface(:not_found), do: "bg-slate-500/10"
  defp page_state_to_surface(:rate_limit), do: "bg-amber-500/10"
  defp page_state_to_surface(:unsupported), do: "bg-amber-500/10"
  defp page_state_to_surface(:error), do: "bg-red-500/10"
end
