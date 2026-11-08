defmodule ExdockWeb.PageLive.LogModal.Entry do
  use ExdockWeb, :html
  alias ExdockWeb.PageLive.Log
  alias ExdockWeb.PageLive.Log.EntryComponents
  alias ExdockWeb.PageLive.Log.EntryViewModel
  alias Exdock.Datetime

  attr :id, :string, required: true
  attr :entry_data, :any, required: true
  attr :message_id, :atom, required: true
  attr :message_data, :any, required: true
  attr :start_time, :any, required: true
  attr :end_time, :any, required: true
  attr :automated, :boolean, required: true

  def render(assigns) do
    assigns =
      assigns
      |> assign(:entry, EntryViewModel.build(assigns.message_id, assigns.message_data))
      |> assign(:entry_status, EntryViewModel.status(assigns.entry_data))

    ~H"""
    <tr id={@id} class="first-divider-subtle-x">
      <td class="w-1/12 ps-2 pe-2 text-center">
        <%= if @automated do %>
          <span class="text-low-visibility">
            <.icon name="hero-calendar" class="w-3 h-3 lg:w-4 lg:h-4 mb-0.5 mr-0" />
          </span>
        <% end %>
      </td>

      <td class="w-1/12 ps-2 pe-2 text-center">
        <EntryComponents.status_icon status={@entry_status} />
      </td>

      <td class="w-1/12 ps-2 pe-2 text-center">
        <%= if not is_nil(@end_time)  do %>
          <span class="text-xs tracking-tighter">
            {DateTime.diff(@end_time, @start_time, :millisecond) / 1000}s
          </span>
        <% end %>
      </td>

      <td class="w-3/12 ps-2 pe-2 text-center">
        <span class="text-xs tracking-tighter">{@start_time |> Datetime.utc_to_timezone() |> Datetime.prettify(:millisecond)}</span>
      </td>

      <td class="w-6/12 ps-2 pe-2">
        <%= case @entry.kind do %>
          <% :container_status -> %>
            <.container_status_entry
              name={@entry.name}
              node={@entry.node}
              old_status={@entry.old_status}
              new_status={@entry.new_status}
            />
          <% :text -> %>
            <.simple_text text={@entry.text} />
          <% :releases_fetch -> %>
            <.releases_entry text={@entry.text} new_releases_count={@entry.new_releases_count} />
          <% :node_refresh -> %>
            <%= if @entry.detailed? do %>
              <.refresh_entry entry={@entry} />
            <% else %>
              <.text_with_list text={@entry.text} list={@entry.nodes} />
            <% end %>
          <% :list -> %>
            <.text_with_list text={@entry.detailed_text} list={@entry.list} />
          <% :node_action -> %>
            <.simple_text text={@entry.detailed_text} />
          <% :node_state -> %>
            <p><span class={@entry.text_color}>{@entry.text}</span> [{@entry.node}]</p>
          <% :limited_entries -> %>
          <% :unknown -> %>
        <% end %>
      </td>
    </tr>
    """
  end

  defp simple_text(assigns) do
    ~H"""
    <p>{@text}</p>
    """
  end

  defp text_with_list(assigns) do
    ~H"""
    <p>{@text} <span class="tracking-tighter">{@list |> inspect()}</span></p>
    """
  end

  defp container_status_entry(assigns) do
    ~H"""
    <p>
      <span class={Log.container_status_to_text_color(@new_status)}>{@name}</span>
      <EntryComponents.container_transition old_status={@old_status} new_status={@new_status} />
      <span>{"node=[#{@node}]"}</span>
    </p>
    """
  end

  defp releases_entry(assigns) do
    ~H"""
    <p class="truncate overflow-hidden w-40 lg:w-48">
      {@text}
      <EntryComponents.release_count count={@new_releases_count} />
    </p>
    """
  end

  defp refresh_entry(assigns) do
    ~H"""
    <details>
      <summary>
        <EntryComponents.refresh_counts counts={@entry.counts} />
        {@entry.text}
        <span class="tracking-tighter">{@entry.nodes |> inspect()}</span>
      </summary>

      <%= for {n,c,s} <- @entry.changes do %>
        <p>
          <%= case s do %>
            <% {:new, _} -> %>
              <.container_change_icon color="text-green-800" container={c} node={n} icon="hero-plus" />
            <% {:ok, :vanished} -> %>
              <.container_change_icon color="text-yellow-800" container={c} node={n} icon="hero-minus" />
            <% {:ok, true} -> %>
              <.container_change_icon color="text-lime-800" container={c} node={n} icon="hero-arrow-long-up" />
            <% {:ok, false} -> %>
              <.container_change_icon color="text-amber-800" container={c} node={n} icon="hero-arrow-long-down" />
            <% {:error, _error} -> %>
              <.container_change_icon color="text-error" container={c} node={n} icon="hero-exclamation-triangle" />
          <% end %>
        </p>
      <% end %>
    </details>
    """
  end

  defp container_change_icon(assigns) do
    ~H"""
    <span class={@color}><.icon name={@icon} class="w-3 h-3 ms-0 mb-0 mr-0" />{"#{@container} [#{@node}]"}</span>
    """
  end
end
