defmodule ExdockWeb.Commons.ContainerManager.StatusMessages do
  use Phoenix.Component
  import ExdockWeb.CoreComponents
  attr :id, :string, required: true
  attr :presentation, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="rounded-lg border border-secondary bg-primary-lighter p-3">
      <div class="flex flex-row">
        <ul class="text-xs text-start text-low-visibility flex flex-col space-y-1">
          <%= for message <- @presentation.status_messages do %>
            <li class="hover:break-all">
              <%= case message do %>
                <% {:running, time, cog_class} -> %>
                  <p class="ms-1">
                    <.icon name="hero-cog" class={["w-4 h-4", "mb-0.5 mr-0", cog_class] |> Enum.join(" ")} /> Container has been
                    <span class="text-success">running </span>
                    for <span
                      id={@id <> "-runtime-duration"}
                      class="text-mid-visibility font-mono tracking-tighter"
                    >{time}</span>.
                  </p>
                <% {:stopped, time} -> %>
                  <p class="ms-1">
                    <.icon name="hero-cog" class="w-4 h-4 text-high-visibility mb-0.5 mr-0" /> Container has been
                    <span class="text-high-visibility">stopped </span>
                    for <span
                      id={@id <> "-runtime-duration"}
                      class="text-mid-visibility font-mono tracking-tighter"
                    >{time}</span>.
                  </p>
                <% {:restarting} -> %>
                  <p class="ms-1">
                    <.icon name="hero-cog" class="w-4 h-4 text-eye-secondary mb-0.5 mr-0" />
                    Container is <span class="text-eye-secondary">restarting </span>.
                  </p>
                <% {:unknown, build_date} -> %>
                  <p class="ms-1">
                    <.icon name="hero-question-mark-circle" class="w-4 h-4 text-container-unknown mb-0.5 mr-0" /> Image is
                    <span class="text-container-unknown italic">unknown</span>
                    and local was built on <span class="text-mid-visibility">{build_date}</span>.
                  </p>
                <% {:updated, build_date} -> %>
                  <p class="ms-1">
                    <.icon name="hero-check" class="w-4 h-4 text-container-updated mb-0.5 mr-0" /> Image is
                    <span class="text-success">up to date </span>
                    and local was built on <span class="text-mid-visibility">{build_date}</span>.
                  </p>
                <% {:outdated, local, remote, days} -> %>
                  <p class="ms-1">
                    <.icon name="hero-arrow-down-on-square" class="w-4 h-4 text-container-outdated mb-0.5 mr-0" /> Image is
                    <span class="text-container-outdated">outdated </span>
                    and local was built on <span class="text-mid-visibility">{local}</span>
                    with latest on <span class="text-mid-visibility">{remote}</span>
                    , <span class="text-mid-visibility">{"#{days}"}</span>
                    days old.
                  </p>
                <% {:error, error} -> %>
                  <p class="ms-1">Image status is <span class="text-error">{"#{error} "}</span>.</p>
                <% {:image_present, true} -> %>
                  <p class="ms-1">
                    <.icon name="hero-check-circle" class="w-4 h-4 text-success-icon mb-0.5 mr-0" /> The updated image
                    <span class="text-success">has</span>
                    been pulled.
                  </p>
                <% {:image_present, false} -> %>
                  <p class="ms-1">
                    <.icon name="hero-no-symbol" class="w-4 h-4 text-error mb-0.5 mr-0" /> The updated image
                    <span class="text-warning">has not</span>
                    been pulled.
                  </p>
              <% end %>
            </li>
          <% end %>
        </ul>
      </div>

      <dl class="mt-3 grid gap-2 border-t border-secondary pt-3">
        <div class="grid gap-1 sm:grid-cols-[6rem_minmax(0,1fr)] sm:items-start">
          <dt class="text-xs font-medium text-low-visibility">Local digest</dt>
          <dd
            id={@id <> "-local-digest"}
            class="break-all font-mono text-xs leading-5 text-mid-visibility"
          >
            {@presentation.local_digest}
          </dd>
        </div>

        <div
          :if={@presentation.show_remote_digest?}
          class="grid gap-1 sm:grid-cols-[6rem_minmax(0,1fr)] sm:items-start"
        >
          <dt class="text-xs font-medium text-low-visibility">Remote digest</dt>
          <dd
            id={@id <> "-remote-digest"}
            class="break-all font-mono text-xs leading-5 text-mid-visibility"
          >
            {@presentation.remote_digest}
          </dd>
        </div>
      </dl>
    </div>
    """
  end
end
