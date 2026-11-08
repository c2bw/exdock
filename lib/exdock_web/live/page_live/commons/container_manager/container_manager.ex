defmodule ExdockWeb.Commons.ContainerManager do
  use ExdockWeb, :live_component
  alias Exdock.ReadModel.{Repository, RepositoryPage}
  alias ExdockWeb.Commons.ContainerManager
  alias ExdockWeb.Commons.ContainerManager.Presentation
  alias ExdockWeb.PageLive.Utils.ContainerSettingsEvents

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign_new(:recreate_pull_image, fn -> false end)
      |> assign(assigns)
      |> assign_new(:action_form, fn -> action_form(false) end)
      |> assign_logs_form_if_changed()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@render?}>
        <.modal id={@modal_id} show max_width="max-w-6xl" panel_class="container-manager-modal">
          <.container_manager_data
            id={@component_id}
            modal_id={@modal_id}
            nodename={@nodename}
            container_name={@container_name}
            core={@core}
            extended={@extended}
            logs_form={@logs_form}
            release_data={@release_data}
            action_form={@action_form}
            myself={@myself}
            clock_now={@clock_now}
          />
        </.modal>
      </div>
    </div>
    """
  end

  defp container_manager_data(assigns) do
    assigns =
      assigns
      |> assign(:release_data, normalize_release_data(assigns.release_data))
      |> assign(
        :presentation,
        Presentation.build(assigns.container_name, assigns.core, assigns.clock_now)
      )

    ~H"""
    <div id={@id <> "surface"} class="-m-6 overflow-hidden rounded-2xl sm:-m-8">
      <h2 id={@modal_id <> "-title"} class="sr-only">Container manager for {@container_name}</h2>

      <p id={@modal_id <> "-description"} class="sr-only">
        Inspect and manage {@container_name} on {@nodename}.
      </p>

      <div class="border-b border-primary bg-primary px-5 pb-4 pt-5 sm:px-7 sm:pb-5 sm:pt-6">
        <ContainerManager.Header.render
          id={@id <> "header"}
          nodename={@nodename}
          container_name={@container_name}
          core={@core}
          target={@myself}
        />
        <ContainerManager.UserActions.render
          id={@id}
          nodename={@nodename}
          container_name={@container_name}
          core={@core}
          action_form={@action_form}
          myself={@myself}
        />
      </div>

      <div
        id={@id <> "scroll-region"}
        class="max-h-[min(72vh,52rem)] overflow-y-auto bg-primary-lighter px-5 py-5 sm:px-7 sm:py-6"
      >
        <div class="grid gap-4 lg:grid-cols-[minmax(0,1.4fr)_minmax(18rem,0.6fr)]">
          <section
            id={@id <> "status-panel"}
            aria-labelledby={@id <> "status-heading"}
            class="rounded-xl border border-primary bg-primary p-4 shadow-sm"
          >
            <div class="mb-3 flex items-center gap-2">
              <span class="grid h-8 w-8 place-items-center rounded-lg bg-secondary text-eye">
                <.icon name="hero-signal" class="h-4 w-4" />
              </span>

              <div>
                <h2 id={@id <> "status-heading"} class="text-sm font-semibold text-high-visibility">Health & status</h2>
              </div>
            </div>
            <ContainerManager.InfoMessages.render messages={@presentation.info_messages} />
            <ContainerManager.StatusMessages.render
              id={@id <> "status"}
              presentation={@presentation}
            />
          </section>

          <section
            id={@id <> "resources-panel"}
            aria-labelledby={@id <> "resources-heading"}
            class="rounded-xl border border-primary bg-primary p-4 shadow-sm"
          >
            <div class="mb-3 flex items-center gap-2">
              <span class="grid h-8 w-8 place-items-center rounded-lg bg-secondary text-eye">
                <.icon name="hero-chart-bar" class="h-4 w-4" />
              </span>

              <div>
                <h2 id={@id <> "resources-heading"} class="text-sm font-semibold text-high-visibility">Live resources</h2>

                <p class="text-xs text-low-visibility">Current usage and cumulative totals</p>
              </div>
            </div>
            <ContainerManager.Resources.render core={@core} extended={@extended} />
          </section>
        </div>

        <div class="mt-4 space-y-4">
          <section class="rounded-xl border border-primary bg-primary p-4 shadow-sm sm:p-5">
            <div class="mb-4 flex items-center gap-2">
              <span class="grid h-8 w-8 place-items-center rounded-lg bg-secondary text-eye">
                <.icon name="hero-adjustments-horizontal" class="h-4 w-4" />
              </span>

              <div>
                <h2 class="text-sm font-semibold text-high-visibility">Configuration & diagnostics</h2>

                <p class="text-xs text-low-visibility">Container metadata, inspect output, and logs</p>
              </div>
            </div>

            <ContainerManager.Configuration.render
              id={@id <> "configuration"}
              nodename={@nodename}
              container_name={@container_name}
              core={@core}
              extended={@extended}
              logs_form={@logs_form}
              clock_now={@clock_now}
            />
          </section>

          <section class="rounded-xl border border-primary bg-primary p-4 shadow-sm sm:p-5">
            <ContainerManager.Repository.render id={@id} core={@core} />
          </section>

          <section class="rounded-xl border border-primary bg-primary p-4 shadow-sm sm:p-5">
            <.live_component
              module={ContainerManager.Releases}
              id={@id <> "releases"}
              repository_url={@core.repository_url}
              page={@release_data.page}
              releases={@release_data.releases}
              clock_now={@clock_now}
            />
          </section>
        </div>
      </div>
    </div>
    """
  end

  defp normalize_release_data(%Repository{page: page, releases: releases}) do
    %{page: page || %RepositoryPage{}, releases: releases || []}
  end

  defp normalize_release_data(_release_data), do: %{page: %RepositoryPage{}, releases: []}

  @impl true
  def handle_event("change_recreate_options", %{"image_pull" => image_pull}, socket) do
    socket =
      socket
      |> assign(:recreate_pull_image, image_pull == "true")
      |> assign_action_form()

    {:noreply, socket}
  end

  def handle_event("change_priority", params, socket) do
    result = ContainerSettingsEvents.change_priority(params)
    {:noreply, ContainerSettingsEvents.apply_priority_result(socket, result)}
  end

  def handle_event("change_auto_update", params, socket) do
    result = ContainerSettingsEvents.change_auto_update(params)
    {:noreply, ContainerSettingsEvents.apply_auto_update_result(socket, result)}
  end

  defp assign_action_form(socket),
    do: assign(socket, :action_form, action_form(socket.assigns.recreate_pull_image))

  defp assign_logs_form_if_changed(socket) do
    identity = {socket.assigns.nodename, socket.assigns.container_name}

    if socket.assigns[:logs_form_identity] == identity do
      socket
    else
      socket
      |> assign(:logs_form_identity, identity)
      |> assign(
        :logs_form,
        to_form(%{
          "node" => to_string(socket.assigns.nodename),
          "container_name" => socket.assigns.container_name
        })
      )
    end
  end

  defp action_form(pull_image), do: to_form(%{"image_pull" => to_string(pull_image)})
end
