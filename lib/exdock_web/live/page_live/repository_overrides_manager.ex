defmodule ExdockWeb.PageLive.RepositoryOverridesManager do
  @moduledoc """
  Settings subcomponent for editing image-to-repository URL overrides.

  The component presents the current override map and emits import/update events;
  repository persistence remains owned by server state storage.
  """

  use ExdockWeb, :live_component

  alias ExdockWeb.PageLive.Utils.IdUtils

  @impl true
  def update(assigns, socket) do
    overrides = Enum.sort_by(assigns.repository_overrides, fn {name, _metadata} -> name end)

    socket =
      socket
      |> assign(assigns)
      |> assign(:override_count, length(overrides))
      |> assign_new(:form, fn -> to_form(%{}) end)
      |> stream(:overrides, overrides,
        reset: true,
        dom_id: fn {name, _metadata} -> IdUtils.create_id("repository_override_#{name}") end
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="repository-overrides-manager" class="min-w-0">
      <div class="flex items-start gap-3 pr-10">
        <span class="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-secondary text-eye">
          <.icon name="hero-link" class="h-5 w-5" />
        </span>

        <div>
          <div class="flex flex-wrap items-center gap-2">
            <h2 id={@modal_id <> "-title"} class="text-lg font-semibold tracking-tight text-high-visibility">
              Repository overrides
            </h2>

            <span class="rounded-full border border-primary bg-primary px-2 py-0.5 text-[0.675rem] font-semibold text-mid-visibility">
              {@override_count}
            </span>
          </div>

          <p id={@modal_id <> "-description"} class="mt-1 text-xs leading-5 text-low-visibility">
            Map container images to their source repositories for release discovery and metadata.
          </p>
        </div>
      </div>

      <section aria-labelledby="current-overrides-heading" class="mt-6">
        <div class="mb-2 flex items-end justify-between gap-3">
          <div>
            <h3 id="current-overrides-heading" class="text-sm font-semibold text-high-visibility">Current rules</h3>

            <p class="mt-0.5 text-[0.675rem] text-low-visibility">Image names are matched independently of their tag.</p>
          </div>
        </div>

        <div class="max-h-64 overflow-auto rounded-xl border border-primary bg-primary">
          <table class="w-full min-w-[34rem] border-collapse text-left">
            <thead class="sticky top-0 z-10 bg-secondary text-[0.625rem] font-semibold uppercase tracking-wider text-low-visibility">
              <tr>
                <th class="px-4 py-2.5">Image</th>

                <th class="w-8 px-1 py-2.5"><span class="sr-only">maps to</span></th>

                <th class="px-4 py-2.5">Repository destination</th>
              </tr>
            </thead>

            <tbody id="repository-overrides" phx-update="stream" class="divide-y divide-primary">
              <tr id="repository-overrides-empty" class="hidden only:table-row">
                <td colspan="3" class="px-4 py-8 text-center">
                  <.icon name="hero-link-slash" class="h-5 w-5 text-low-visibility" />
                  <p class="mt-2 text-xs font-medium text-mid-visibility">No custom rules yet</p>

                  <p class="mt-0.5 text-[0.675rem] text-low-visibility">Import a rule below to add the first override.</p>
                </td>
              </tr>

              <tr
                :for={{dom_id, {name, %{repository_url: repository_url}}} <- @streams.overrides}
                id={dom_id}
                class="group text-xs text-mid-visibility transition-colors hover:bg-secondary"
              >
                <td class="px-4 py-3 font-mono font-semibold text-high-visibility">{name}</td>

                <td class="px-1 py-3 text-center text-low-visibility">
                  <.icon name="hero-arrow-right" class="h-3.5 w-3.5" />
                </td>

                <td class="px-4 py-3">
                  <a
                    href={repository_url}
                    target="_blank"
                    rel="noreferrer"
                    class="inline-flex items-center gap-1.5 font-mono transition hover:text-high-visibility"
                  >
                    <span>{repository_url}</span>
                    <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5 shrink-0 opacity-60" />
                  </a>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section aria-labelledby="import-overrides-heading" class="mt-6 rounded-xl border border-primary bg-primary p-4">
        <div class="flex items-start gap-2">
          <span class="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-secondary text-eye">
            <.icon name="hero-arrow-down-tray" class="h-4 w-4" />
          </span>

          <div>
            <h3 id="import-overrides-heading" class="text-sm font-semibold text-high-visibility">Bulk import</h3>

            <p class="mt-0.5 text-[0.675rem] leading-5 text-low-visibility">
              Enter one rule per line using <code class="rounded bg-secondary px-1 py-0.5 font-mono text-mid-visibility">image -&gt; URL</code>.
            </p>
          </div>
        </div>

        <.form for={@form} id="repository-overrides-import-form" phx-submit="import_repository_overrides" class="mt-3">
          <.input
            type="textarea"
            field={@form[:repositories_input]}
            id="repositories_input"
            label="Override rules"
            rows="6"
            placeholder="alpine:latest -> https://github.com/alpinelinux/docker-alpine"
            bg_color="bg-primary-lighter"
            text_color="text-high-visibility"
            custom_classes="font-mono text-xs leading-5"
          />
          <div class="mt-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <p class="text-[0.675rem] text-low-visibility">Existing image rules with the same name will be updated.</p>

            <button
              id="repository-overrides-import-button"
              type="submit"
              class="inline-flex h-9 items-center justify-center gap-2 rounded-lg border border-[var(--accent)] bg-[var(--accent)] px-4 text-xs font-semibold text-core-component shadow-sm transition hover:brightness-110 active:translate-y-px"
            >
              <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> Import rules
            </button>
          </div>
        </.form>
      </section>
    </div>
    """
  end
end
