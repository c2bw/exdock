defmodule ExdockWeb.PageLive.StatusModal do
  use ExdockWeb, :html

  alias Exdock.Status.Dashboard.Row
  alias ExdockWeb.PageLive.StatusModal.ViewModel

  attr :id, :string, required: true
  attr :dash, :map, required: true
  attr :has_errors, :boolean, required: true
  attr :errors_log, :list, required: true

  def render(assigns) do
    assigns = assign(assigns, :view_model, ViewModel.build(assigns.dash, assigns.has_errors, assigns.errors_log))

    ~H"""
    <div id={@id} class="overflow-auto">
      <p class="modal-title mb-1">Detailed Status</p>

      <%= if @view_model.has_errors? do %>
        <p class="font-thin text-xs font-mono text-center text-low-visibility mb-1">
          <button id="clear-status-errors" class="inline" phx-click="clear_errors">
            clear alerts
          </button>
        </p>
      <% end %>

      <div class="flex flex-col space-y-2">
        <div class="flex">
          <p class="font-mono font-semibold text-sm">
            <%= if @view_model.nodes.awaiting? do %>
              Nodes - Awaiting
              <span class="text-sm">
                [<span class="text-xs font-normal">
                  <%= for entry <- @view_model.nodes.entries do %>
                    <span class={entry.state == :error && "text-error"}>{entry.node}</span>
                  <% end %>
                </span>]
              </span>
            <% else %>
              <span class="text-sm">
                Nodes [ <span class="text-xs text-success">All nodes refreshed</span> ]
              </span>
            <% end %>
          </p>
        </div>

        <.progress_status :for={progress <- @view_model.progress} progress={progress} />

        <.action_group :for={group <- @view_model.action_groups} group={group} />

        <div class="flex flex-col">
          <div class="flex">
            <p class="inline font-mono font-semibold text-sm">
              Errors and warnings log
              <%= if @view_model.errors_log == [] do %>
                <span class="font-bold text-success"> no alerts</span>
              <% end %>
            </p>
          </div>

          <%= if @view_model.errors_log != [] do %>
            <div class="flex w-full max-h-44 overflow-auto">
              <table class="m-0 table-auto w-full font-mono bg-primary rounded border-primary border">
                <tbody class="first-row-divider-subtle text-low-visibility text-left font-mono divide-y divide-primary whitespace-nowrap">
                  <%= for {time_string, error_message} <- @view_model.errors_log do %>
                    <tr class="first-divider-subtle-x text-error">
                      <td class="ps-1 pe-1 text-start text-xs tracking-tighter">
                        {time_string}
                      </td>
                      <td class="ps-1 pe-1 text-start text-xs tracking-tighter">
                        {error_message}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :progress, :map, required: true

  defp progress_status(assigns) do
    ~H"""
    <div class="flex">
      <p class="font-mono font-semibold text-sm">
        {@progress.title}
        <%= if @progress.active? do %>
          <span class="text-xs font-normal">
            {@progress.fetched} of {@progress.total} {@progress.unit} processed
          </span>
        <% else %>
          <span class="font-bold text-success">OK</span>
        <% end %>
      </p>
    </div>
    """
  end

  attr :group, :map, required: true

  defp action_group(assigns) do
    ~H"""
    <div class="flex flex-col">
      <div class="flex">
        <p class="inline font-mono font-semibold text-sm">
          {@group.title}
          <%= if @group.empty? do %>
            <span class="font-bold text-success"> OK </span>
          <% end %>
        </p>
      </div>

      <div class="flex flex-col">
        <%= for action <- @group.actions do %>
          <%= if action.entries != [] do %>
            <div class="flex flex-col">
              <div class="flex justify-center bg-primary border-primary border">
                <p class="inline font-mono font-semibold text-xs text-mid-visibility text-center">
                  {action.label}
                </p>
              </div>

              <div class="flex w-full max-h-44 overflow-auto">
                <table class="m-0 table-auto w-full font-mono bg-primary rounded border-primary border">
                  <tbody class="first-row-divider-subtle text-low-visibility text-left font-mono divide-y divide-primary whitespace-nowrap">
                    <%= for entry <- action.entries do %>
                      <tr class={status_row_class(entry.row)}>
                        <td class={["ps-2 pe-2 text-start", action.item_class]}>{entry.item}</td>
                        <td class="ps-2 pe-2 text-start text-xs">{"[#{entry.node}]"}</td>
                        <%= if action.show_message? and status_message(entry.row) do %>
                          <td class="ps-2 pe-2 text-start text-xs w-full">
                            {status_message(entry.row)}
                          </td>
                        <% end %>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_message(%Row{message: {:string, message}}), do: message
  defp status_message(%Row{message: nil}), do: nil
  defp status_message(%Row{message: message}), do: inspect(message)

  defp status_row_class(%Row{state: {:error, _error}}),
    do: "first-divider-subtle-x text-error"

  defp status_row_class(%Row{state: {:warning, _warning}}),
    do: "first-divider-subtle-x text-amber-600 dark:text-amber-400"

  defp status_row_class(%Row{}), do: "first-divider-subtle-x"
end
