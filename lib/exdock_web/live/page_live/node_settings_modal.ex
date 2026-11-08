defmodule ExdockWeb.PageLive.NodeSettingsModal do
  use ExdockWeb, :html

  attr :id, :string, required: true
  attr :form, :any, required: true
  attr :settings, :any, required: true
  attr :node, :any, required: true

  def render(assigns) do
    ~H"""
    <div class="overflow-auto">
      <p class="modal-title mb-0">
        Node Settings
        <p class="font-mono font-semibold text-center"><span class="text-low-visibility">{@node}</span></p>
      </p>

      <div class="mt-4 pt-3 p-2 border-t border-primary overflow-auto">
        <.form for={@form} id={@id <> "-form"} phx-submit="change_node_settings">
          <div class="flex flex-row w-full">
            <div class="flex me-4 min-w-24">
              <p class="font-mono whitespace-nowrap text-mid-visibility mt-1">Web UI</p>
            </div>

            <div class="flex grow">
              <.input type="hidden" field={@form[:node]} id={"nodesettings_node_input"<> to_string(@node)} />
              <.input type="hidden" field={@form[:key]} id={"nodesettings_key_input"<> to_string(@node)} />
              <.input
                type="text"
                field={@form[:val]}
                id={"web_ui_input" <> to_string(@node)}
                placeholder={if @settings.web_ui == "", do: "currently not set", else: @settings.web_ui}
                bg_color="bg-primary"
                text_color="text-high-visibility"
                custom_classes="text-start text-xs tracking-tighter font-mono max-sm:min-w-56 max-md:min-w-64 min-w-96 flex grow h-8"
              />
            </div>

            <div class="flex justify-end ">
              <button class="ms-2 me-2 btn-secondary">
                <span class="px-4"> set </span>
              </button>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
