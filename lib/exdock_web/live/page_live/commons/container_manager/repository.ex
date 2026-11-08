defmodule ExdockWeb.Commons.ContainerManager.Repository do
  use Phoenix.Component
  import ExdockWeb.CoreComponents

  attr :id, :string, required: true
  attr :core, :map, required: true

  def render(assigns) do
    assigns = assign(assigns, :repository_form, to_form(%{}))

    ~H"""
    <div id={@id <> "repository-override"}>
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div class="flex items-center gap-3">
          <span class="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-secondary text-eye">
            <.icon name="hero-link" class="h-4 w-4" />
          </span>

          <div>
            <h2 class="text-sm font-semibold text-high-visibility">Repository URL override</h2>

            <p class="mt-0.5 text-xs text-low-visibility">
              Choose where Exdock looks for releases and project metadata.
            </p>
          </div>
        </div>

        <span class="max-w-full self-start truncate rounded-md border border-secondary bg-primary-lighter px-2 py-1 font-mono text-[0.675rem] text-mid-visibility">
          {@core.image_tag}
        </span>
      </div>

      <div class="mt-4 rounded-lg border border-secondary bg-primary-lighter p-3 sm:flex sm:items-center sm:justify-between sm:gap-4">
        <div class="min-w-0">
          <p class="text-[0.625rem] font-semibold uppercase tracking-wider text-low-visibility">Current destination</p>

          <a
            id={@id <> "repository-current-url"}
            href={@core.repository_url}
            target="_blank"
            rel="noreferrer"
            class="mt-1 flex min-w-0 items-center gap-1.5 font-mono text-xs font-semibold text-mid-visibility transition hover:text-high-visibility"
          >
            <span class="break-all">{@core.repository_url}</span>
            <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4 shrink-0" />
          </a>
        </div>
      </div>

      <.form
        for={@repository_form}
        id={@id <> "repository-url-form"}
        phx-submit="repository-url-update"
        class="mt-4"
      >
        <.input
          type="hidden"
          field={@repository_form[:img_name]}
          id={@id <> "imgname"}
          value={@core.image_tag}
        />
        <div class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end">
          <.input
            type="url"
            field={@repository_form[:new_url]}
            id={@id <> "new_url"}
            label="New repository URL"
            placeholder="https://github.com/organization/project"
            autocomplete="url"
            required
            bg_color="bg-primary-lighter"
            text_color="text-high-visibility"
            custom_classes="font-mono text-xs"
          />
          <button
            id={@id <> "repository-save"}
            type="submit"
            class="inline-flex h-10 items-center justify-center gap-2 rounded-lg border border-[var(--accent)] bg-[var(--accent)] px-4 text-xs font-semibold text-core-component shadow-sm transition hover:brightness-110 active:translate-y-px"
          >
            <.icon name="hero-check" class="h-4 w-4" /> Save override
          </button>
        </div>
      </.form>

      <p class="mt-2 flex items-start gap-1.5 text-[0.675rem] leading-5 text-low-visibility">
        <.icon name="hero-information-circle" class="mt-0.5 h-3.5 w-3.5 shrink-0" />
        The rule follows the image name across tags and every container using that image.
      </p>
    </div>
    """
  end
end
