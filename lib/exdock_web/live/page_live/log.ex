defmodule ExdockWeb.PageLive.Log do
  @moduledoc """
  LiveComponent for rendering server log lines in page sidebars/modals.

  It receives already-collected log data from the parent LiveView and stays
  presentation-only.
  """

  use ExdockWeb, :html
  alias ExdockWeb.PageLive.Utils.IdUtils
  alias ExdockWeb.PageLive.Utils.ModalState

  @max_entries 50

  attr :id, :string, required: true
  attr :modals_to_render, :map, required: true
  attr :log, :list, required: true

  def render(assigns) do
    ~H"""
    <div class="flex border border-primary rounded bg-above-primary">
      <div class="w-full">
        <p
          class="text-left mx-0 border-b border-primary bg-hover text-high-visibility hover:cursor-pointer"
          phx-click={show_lazy_modal("log-component-modal")}
        >
          <.icon name="hero-clipboard-document-list" class="w-5 h-5 mb-1 mr-0" /> <span class="font-mono font-semibold">Log</span>
        </p>

        <div class="log-scroll w-full overflow-y-auto overflow-x-hidden max-h-96">
          <table class="ms-0 me-1 mb-1.5 mt-1 font-mono text-xs text-low-visibility font-semibold w-48 lg:w-56">
            <tbody class="log-entry-dividers text-left whitespace-nowrap">
              <%= for logline <- if(@log == [], do: [placeholder(:no_log)], else: filter_entries(@log)) do %>
                <%= if not logline.hidden do %>
                  <ExdockWeb.PageLive.Log.Entry.render
                    id={"logentry#{logline.id}" |> IdUtils.create_id()}
                    entry_data={logline.entry_data}
                    message_id={logline.message_id}
                    message_data={logline.message_data}
                  />
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

      <.modal id="log-component-modal">
        <.live_component
          module={ExdockWeb.PageLive.LogModal}
          id="log-component-modal-lc"
          render?={ModalState.render?(@modals_to_render, "log-component-modal")}
          log={@log}
        />
      </.modal>
    </div>
    """
  end

  def container_status_to_text_color(status) do
    cond do
      status == :new_container -> "text-container-unknown"
      status not in [:unknown, :outdated, :updated] -> "text-container-errored"
      status == :unknown -> "text-container-unknown"
      status == :outdated -> "text-container-outdated"
      status == :updated -> "text-container-updated"
    end
  end

  def container_status_to_icon_name(status) do
    cond do
      status == :new_container -> "hero-plus"
      status not in [:unknown, :outdated, :updated] -> "hero-exclamation-triangle"
      status == :unknown -> "hero-question-mark-circle"
      status == :outdated -> "hero-arrow-down-on-square"
      status == :updated -> "hero-check"
    end
  end

  # Filter out entries that are not supposed to be shown
  # Limit the amount of entries
  defp filter_entries(entries) do
    filtered =
      entries
      |> Enum.reject(fn e -> e.message_id in [:container_logs] end)
      |> Enum.take(@max_entries)

    case length(filtered) == @max_entries do
      true -> filtered ++ [placeholder(:limited_entries)]
      false -> filtered
    end
  end

  defp placeholder(message_id) do
    %{
      id: to_string(message_id),
      entry_data: nil,
      hidden: false,
      message_id: message_id,
      message_data: nil
    }
  end
end
