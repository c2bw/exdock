defmodule ExdockWeb.PageLive.SettingsPage do
  @moduledoc """
  Lazy-rendered settings modal for user, node, repository, and import options.

  Changes are emitted as shared LiveView events handled by `CommonPageHandler`,
  which applies them through the server state owner.
  """

  use ExdockWeb, :html
  alias ExdockWeb.{SettingsCatalog, SettingsControls}

  attr :id, :string, required: true
  attr :configuration_form, :any, required: true
  attr :render?, :boolean, required: true
  attr :server_configuration, :any, required: true

  def render(assigns) do
    ~H"""
    <div id={@id} class="settings-modal max-h-[min(82vh,54rem)] overflow-y-auto pr-1">
      <header class="settings-modal-header">
        <span class="control-icon-tile settings-modal-icon" aria-hidden="true">
          <.icon name="hero-adjustments-horizontal" class="h-5 w-5" />
        </span>
        <div>
          <h2 class="text-lg font-semibold tracking-tight text-high-visibility">Settings</h2>
          <p class="mt-0.5 text-xs text-low-visibility">
            Configure how Exdock monitors and manages your environment.
          </p>
        </div>
      </header>

      <div class="space-y-3">
        <.user_settings settings={@server_configuration.user_settings} />
        <.managers render={@render?} repository_overrides={@server_configuration.repository_overrides} />
        <.configuration
          form={@configuration_form}
          render={@render?}
          server_configuration={@server_configuration}
        />
      </div>
    </div>
    """
  end

  defp user_settings(assigns) do
    assigns = assign(assigns, :controls, SettingsCatalog.toggles(:preferences))

    ~H"""
    <section id="settings-preferences" class="settings-section" aria-labelledby="settings-preferences-title">
      <div class="settings-section-heading">
        <span class="control-icon-tile settings-section-icon" aria-hidden="true">
          <.icon name="hero-adjustments-vertical" class="h-4 w-4" />
        </span>
        <div>
          <h3 id="settings-preferences-title" class="settings-section-title">Preferences</h3>
          <p class="settings-section-description">Choose the features used throughout the dashboard.</p>
        </div>
      </div>

      <div class="mt-2 space-y-0.5">
        <SettingsControls.toggle
          :for={control <- @controls}
          id={"settings-toggle-#{control.external}"}
          text={control.label}
          enabled={Map.fetch!(@settings, control.key)}
          on_click={control.event}
          setting_key={control.external}
        />
      </div>
    </section>
    """
  end

  defp managers(assigns) do
    ~H"""
    <section id="settings-management" class="settings-section" aria-labelledby="settings-management-title">
      <div class="settings-section-heading">
        <span class="control-icon-tile settings-section-icon" aria-hidden="true">
          <.icon name="hero-wrench-screwdriver" class="h-4 w-4" />
        </span>
        <div>
          <h3 id="settings-management-title" class="settings-section-title">Management</h3>
          <p class="settings-section-description">Open detailed controls for repositories and priorities.</p>
        </div>
      </div>

      <div class="mt-3 grid gap-2">
        <button
          id="manage-repository-overrides-button"
          type="button"
          class="control-lift-action settings-management-action"
          phx-click={show_modal("manage-repositories-overrides")}
        >
          <span class="control-icon-tile settings-management-action-icon" aria-hidden="true">
            <.icon name="hero-link" class="h-4 w-4" />
          </span>
          <span class="min-w-0 text-left">
            <span class="block text-sm font-semibold text-high-visibility">Repository overrides</span>
            <span class="mt-0.5 block text-xs text-low-visibility">Customize image source links</span>
          </span>
          <.icon name="hero-chevron-right" class="ml-auto h-4 w-4 shrink-0 text-low-visibility" />
        </button>

        <.link
          id="manage-container-priorities-link"
          navigate={~p"/priorities"}
          class="control-lift-action settings-management-action"
        >
          <span class="control-icon-tile settings-management-action-icon" aria-hidden="true">
            <.icon name="hero-bars-arrow-up" class="h-4 w-4" />
          </span>
          <span class="min-w-0 text-left">
            <span class="block text-sm font-semibold text-high-visibility">Container priorities</span>
            <span class="mt-0.5 block text-xs text-low-visibility">Control update order</span>
          </span>
          <.icon name="hero-arrow-top-right-on-square" class="ml-auto h-4 w-4 shrink-0 text-low-visibility" />
        </.link>
      </div>

      <div :if={@render}>
        <.modal id="manage-repositories-overrides">
          <.live_component
            module={ExdockWeb.PageLive.RepositoryOverridesManager}
            id="repositories-overrides-manager"
            modal_id="manage-repositories-overrides"
            repository_overrides={@repository_overrides}
          />
        </.modal>
      </div>
    </section>
    """
  end

  defp configuration(assigns) do
    ~H"""
    <section
      id="settings-server-configuration"
      class="settings-section"
      aria-labelledby="settings-configuration-title"
    >
      <div class="settings-section-heading">
        <span class="control-icon-tile settings-section-icon" aria-hidden="true">
          <.icon name="hero-code-bracket-square" class="h-4 w-4" />
        </span>
        <div>
          <h3 id="settings-configuration-title" class="settings-section-title">Server configuration</h3>
          <p class="settings-section-description">Review or import the complete configuration as JSON.</p>
        </div>
      </div>

      <.form
        for={@form}
        id="server-configuration-import-form"
        phx-submit="import_server_configuration"
        class="mt-3 w-full"
      >
        <div class="settings-code-editor">
          <div class="settings-code-editor-bar">
            <span class="flex items-center gap-1.5">
              <span class="h-1.5 w-1.5 rounded-full bg-emerald-500" aria-hidden="true"></span> configuration.json
            </span>
            <span>JSON</span>
          </div>
          <.input
            type="textarea"
            field={@form[:server_configuration]}
            id="server_configuration_textarea"
            placeholder="{}"
            bg_color="bg-primary"
            text_color="text-mid-visibility"
            custom_classes="settings-configuration-textarea h-72 overflow-auto border-0 p-3 text-start text-xs tracking-tight font-mono sm:h-80"
            spellcheck="false"
          />
        </div>

        <button
          id="import-server-configuration-button"
          type="submit"
          class="control-lift-action settings-import-button"
        >
          <.icon name="hero-arrow-up-tray" class="h-4 w-4" /> Import configuration
        </button>
      </.form>
    </section>
    """
  end
end
