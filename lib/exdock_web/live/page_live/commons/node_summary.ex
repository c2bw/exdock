defmodule ExdockWeb.Commons.NodeSummary do
  @moduledoc """
  Stateless node summary row.

  Data shaping lives in `ViewModel`, while the rendered sections are stateless
  function components.
  """

  use ExdockWeb, :html

  alias Exdock.Datetime
  alias ExdockWeb.Commons.NodeSummary.Actions
  alias ExdockWeb.Commons.NodeSummary.HardwareUsage
  alias ExdockWeb.Commons.NodeSummary.Overview
  alias ExdockWeb.Commons.NodeSummary.Status
  alias ExdockWeb.Commons.NodeSummary.ViewModel
  alias ExdockWeb.PageLive.Utils.IdUtils

  attr :id, :string, required: true
  attr :on_click, :any, required: true
  attr :summary_type, :atom, required: true, values: [:containers, :images]
  attr :nodename, :any, required: true
  attr :node_settings, :any, required: true
  attr :node_last_fetch, :any, required: true
  attr :node_info, :map, required: true
  attr :node_metadata, :map, default: %{}
  attr :containers, :any, default: []
  attr :containers_extended, :map, default: %{}
  attr :resource_rows, :list, default: nil
  attr :show_hardware_usage, :boolean, default: false
  attr :clock_now, :any, required: true
  attr :modals_to_render, :map, default: %{}

  def render(assigns) do
    assigns =
      assigns
      |> assign(:node_settings_form, node_settings_form(assigns.nodename))
      |> assign(:last_fetch, assigns.node_last_fetch)
      |> assign(
        :fetch_staleness,
        Datetime.elapsed_to_staleness(assigns.node_last_fetch, assigns.clock_now)
      )
      |> assign(
        :since_last_fetch,
        Datetime.elapsed_since(assigns.node_last_fetch, assigns.clock_now)
      )
      |> then(&assign(&1, :view_model, ViewModel.new(&1)))
      |> assign(:modal_id, IdUtils.create_id("node-settings" <> assigns.id))

    ~H"""
    <div>
      <div
        id={"#{@id}-header"}
        class={[
          "group relative overflow-hidden rounded-xl border border-secondary bg-primary-lighter shadow-sm",
          "transition-all duration-200 ease-out hover:-translate-y-px hover:border-[var(--accent)] hover:bg-secondary hover:shadow-lg hover:ring-1 hover:ring-[var(--accent)] hover:ring-inset",
          "focus-within:border-[var(--accent)] focus-within:shadow-[inset_0_0_0_1px_var(--accent)]",
          "active:translate-y-0 phx-click-loading:opacity-70"
        ]}
        phx-click={@on_click}
      >
        <span
          aria-hidden="true"
          class="absolute inset-y-2 left-0 w-0.5 rounded-r-full bg-[var(--accent)] opacity-40 transition-all duration-200 group-hover:inset-y-1.5 group-hover:opacity-100"
        ></span>
        <div class="relative flex min-h-12 list-none cursor-pointer flex-nowrap items-center rounded-xl text-high-visibility">
          <Overview.render model={@view_model} /> <Status.render model={@view_model} />
          <Actions.render model={@view_model} modal_id={@modal_id} />
        </div>
      </div>

      <HardwareUsage.render
        :if={assigns[:show_hardware_usage] && @view_model.resource_rows != []}
        id={"#{@id}-hardware-usage"}
        platform={@view_model.platform}
        rows={@view_model.resource_rows}
      />

      <.modal id={@modal_id}>
        <ExdockWeb.PageLive.NodeSettingsModal.render
          id={IdUtils.create_id("node-settings-component" <> @id)}
          form={@node_settings_form}
          settings={@node_settings}
          node={@nodename}
        />
      </.modal>
    </div>
    """
  end

  defp node_settings_form(node) do
    to_form(%{"node" => to_string(node), "key" => "web_ui", "val" => ""})
  end
end
