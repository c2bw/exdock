defmodule ExdockWeb.PageLive.LogModal do
  use ExdockWeb, :live_component

  @preload_entries_count 60

  @impl true
  def update(%{id: _id, log: log, render?: render} = assigns, socket) do
    entries =
      log
      |> then(&if(render, do: &1, else: Enum.take(&1, @preload_entries_count)))
      |> Enum.reject(& &1.hidden)

    socket =
      socket
      |> assign(Map.drop(assigns, [:log]))
      |> stream(:log_entries, entries, reset: true)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="overflow-auto">
      <p class="modal-title mb-2">Detailed Logs</p>

      <div class="w-full">
        <table class="m-0 table-auto w-full font-mono rounded overflow-auto bg-primary">
          <tbody
            id="log-modal-entries"
            phx-update="stream"
            class="log-entry-dividers text-left font-mono text-xs whitespace-nowrap text-low-visibility"
          >
            <%= for {id, logline} <- @streams.log_entries do %>
              <ExdockWeb.PageLive.LogModal.Entry.render
                id={id}
                entry_data={logline.entry_data}
                message_id={logline.message_id}
                message_data={logline.message_data}
                start_time={logline.start_time}
                end_time={logline.end_time}
                automated={logline.is_automated}
              />
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
