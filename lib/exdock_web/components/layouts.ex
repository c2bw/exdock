defmodule ExdockWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. Controllers can use the "app" layout through their
  configured layout, while LiveViews wrap their templates explicitly with
  `Layouts.app/1`.
  """
  use ExdockWeb, :html

  embed_templates "layouts/*"

  @doc """
  Shows the application flash group with standard titles and connection errors.

  ## Examples

      <Layouts.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
      <.flash kind={:warning} title={gettext("Warning!")} flash={@flash} />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {gettext("Attempting to reconnect")} <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        {gettext("Hang in there while we get back on track")} <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :page, :string, required: true, values: ["loading", "error", "loaded"]
  attr :flash, :map, required: true
  attr :current_user, :any, default: nil
  attr :configuration_form, :any, default: nil
  attr :modals_to_render, :map, default: %{}
  attr :server_configuration, :any, default: nil
  slot :inner_block, required: true

  @doc """
  Renders the common LiveView page lifecycle and shell.

  Loading and error states stay inside the application layout. Loaded pages
  receive the render-statistics root and the shared about/settings modals around
  their page-specific content.
  """
  def live_page(assigns) do
    ~H"""
    <.app flash={@flash} current_user={@current_user}>
      <%= case @page do %>
        <% "loading" -> %>
          <.page_state state={:loading} />
        <% "error" -> %>
          <.page_state state={:error} />
        <% "loaded" -> %>
          <div class="h-screen flex flex-1" id={@id} phx-hook="RenderStatistics">
            {render_slot(@inner_block)}
            <.shared_page_modals
              configuration_form={@configuration_form}
              modals_to_render={@modals_to_render}
              server_configuration={@server_configuration}
            />
          </div>
      <% end %>
    </.app>
    """
  end

  attr :id, :string, required: true
  attr :content_id, :string, default: nil
  attr :content_width, :atom, values: [:wide, :compact], default: :wide
  attr :content_class, :any, default: nil
  attr :context, :map, required: true
  slot :aside, required: true
  slot :inner_block, required: true

  @doc """
  Renders the shared navigation, status, and content frame for operational pages.
  """
  def operational_page(assigns) do
    assigns =
      assigns
      |> assign(Map.to_list(assigns.context))
      |> assign(:resolved_content_class, operational_content_class(assigns.content_width, assigns.content_class))

    ~H"""
    <.live_page
      id={@id}
      page={@page}
      flash={@flash}
      current_user={@current_user}
      configuration_form={@configuration_form}
      modals_to_render={@modals_to_render}
      server_configuration={@server_configuration}
    >
      <div id={@content_id} class="flex flex-1 mt-12 overflow-x-hidden">
        <ExdockWeb.PageLive.AsideComponent.render
          nodes_list={@nodes_list}
          show_render_stats?={@server_configuration.user_settings.rendering_statistics}
          client_latency={@client_latency}
          js_render_time={@js_render_time}
          server_render_time={@server_render_time}
        >
          <:inner_content>{render_slot(@aside)}</:inner_content>
        </ExdockWeb.PageLive.AsideComponent.render>

        <main class="flex-1 pt-4 p-8 overflow-x-auto">
          <div class={@resolved_content_class}>
            <nav class="text-high-visibility text-l grid grid-cols-1 gap-4 border-b-2 border-primary">
              <ExdockWeb.PageLive.Status.render id="status-component" status={@status} />
            </nav>

            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </.live_page>
    """
  end

  defp operational_content_class(width, extra_class) do
    [
      "flex flex-col space-y-4 h-full overflow-auto",
      width == :wide && "max-lg:min-w-[24rem] max-xl:min-w-[42rem] max-2xl:min-w-[58rem] min-w-[70rem]",
      width == :compact && "max-lg:min-w-[38rem] max-xl:min-w-[44rem] min-w-[54rem]",
      extra_class
    ]
  end

  @doc "Renders the shared full-page loading or error state."
  attr :state, :atom, required: true, values: [:loading, :error]

  def page_state(assigns) do
    ~H"""
    <section
      id={"page-state-#{@state}"}
      class="flex min-h-dvh items-center justify-center px-6 pt-12"
      aria-live="polite"
    >
      <div class="flex max-w-sm flex-col items-center rounded-2xl border border-primary bg-primary-lighter px-10 py-9 text-center shadow-xl shadow-black/5">
        <div class={[
          "mb-5 flex h-11 w-11 items-center justify-center rounded-xl ring-1 ring-primary",
          @state == :loading && "text-eye",
          @state == :error && "bg-error text-white"
        ]}>
          <.icon
            name={if(@state == :loading, do: "hero-arrow-path", else: "hero-exclamation-triangle")}
            class={["h-5 w-5", @state == :loading && "animate-spin"]}
          />
        </div>

        <h1 class="font-mono text-base font-semibold text-high-visibility">
          {if(@state == :loading, do: "Preparing your workspace", else: "Unable to load this page")}
        </h1>

        <p class="mt-2 text-sm leading-6 text-low-visibility">
          {if(@state == :loading,
            do: "Synchronizing the latest cluster state.",
            else: "Check the server connection, then reload to try again."
          )}
        </p>
      </div>
    </section>
    """
  end

  attr :configuration_form, :any, required: true
  attr :modals_to_render, :map, required: true
  attr :server_configuration, :any, required: true

  defp shared_page_modals(assigns) do
    ~H"""
    <.modal id="about-page">
      <ExdockWeb.PageLive.AboutPage.render id="about-page-component" />
    </.modal>

    <.modal id="settings-page">
      <ExdockWeb.PageLive.SettingsPage.render
        id="settings-page-component"
        configuration_form={@configuration_form}
        render?={ExdockWeb.PageLive.Utils.ModalState.render?(@modals_to_render, "settings-page")}
        server_configuration={@server_configuration}
      />
    </.modal>
    """
  end
end
