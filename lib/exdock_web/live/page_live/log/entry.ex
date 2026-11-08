defmodule ExdockWeb.PageLive.Log.Entry do
  use ExdockWeb, :html
  alias ExdockWeb.PageLive.Log
  alias ExdockWeb.PageLive.Log.EntryComponents
  alias ExdockWeb.PageLive.Log.EntryViewModel
  alias ExdockWeb.PageLive.Utils.URLParam

  attr :id, :string, required: true
  attr :entry_data, :any, required: true
  attr :message_id, :atom, required: true
  attr :message_data, :any, required: true

  def render(assigns) do
    assigns =
      assigns
      |> assign(:entry, EntryViewModel.build(assigns.message_id, assigns.message_data))
      |> assign(:entry_status, EntryViewModel.status(assigns.entry_data))

    ~H"""
    <tr class="first-divider-subtle-x text-left pt-0.5 pb-0.5">
      <td class="w-1/12 ps-1 pe-1 text-center">
        <EntryComponents.status_icon status={@entry_status} />
      </td>

      <td class="w-11/12 ps-2 pe-1">
        <%= case @entry.kind do %>
          <% :container_status -> %>
            <.container_status
              node={@entry.node}
              name={@entry.name}
              old_status={@entry.old_status}
              new_status={@entry.new_status}
            />
          <% :text -> %>
            <.simple_text text={@entry.text} />
          <% :releases_fetch -> %>
            <.releases_entry text={@entry.text} new_releases_count={@entry.new_releases_count} />
          <% :node_refresh -> %>
            <.refresh_entry text={@entry.text} counts={@entry.counts} />
          <% :list -> %>
            <.simple_text text={@entry.text} />
          <% :node_action -> %>
            <.two_line_node node={@entry.node} text={@entry.text} text_color="text-low-visibility" />
          <% :node_state -> %>
            <.one_line_node node={@entry.node} text={@entry.text} text_color={@entry.text_color} />
          <% :limited_entries -> %>
            <p
              class="bg-hover-tertiary text-center text-low-visibility hover:cursor-pointer"
              phx-click={show_lazy_modal("log-component-modal")}
            >
              ...
            </p>
          <% :unknown -> %>
        <% end %>
      </td>
    </tr>
    """
  end

  defp simple_text(assigns) do
    ~H"""
    <p class="truncate overflow-hidden w-40 lg:w-48"><span class="text-low-visibility">{@text}</span></p>
    """
  end

  defp one_line_node(assigns) do
    ~H"""
    <p class="truncate overflow-hidden w-40 lg:w-48">
      <span class={@text_color}>{@text}</span> <.link_to_node node={@node} />
    </p>
    """
  end

  defp two_line_node(assigns) do
    ~H"""
    <p class="truncate overflow-hidden w-40 lg:w-48"><span class={@text_color}>{@text}</span></p>

    <p class="truncate overflow-hidden w-40 lg:w-48"><.link_to_node node={@node} /></p>
    """
  end

  defp link_to_node(assigns) do
    ~H"""
    <.link navigate={~p"/containers/#{URLParam.encode(@node)}"}>
      <span class="text-hover-high-visibility">[{@node}]</span>
    </.link>
    """
  end

  defp container_status(assigns) do
    ~H"""
    <table class="m-0 table-auto font-mono">
      <tbody class="text-low-visibility text-left font-mono text-xs">
        <tr>
          <td class="truncate overflow-hidden">
            <p class="w-24 lg:w-28 truncate overflow-hidden">
              <span class={Log.container_status_to_text_color(@new_status)}>{@name}</span>
            </p>
          </td>

          <td class="space-x-1 px-1 text-center">
            <EntryComponents.container_transition old_status={@old_status} new_status={@new_status} />
          </td>
        </tr>
      </tbody>
    </table>

    <p class="truncate overflow-hidden w-40 lg:w-48"><.link_to_node node={@node} /></p>
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
    <p class="truncate overflow-hidden w-40 lg:w-48">
      {@text}
      <EntryComponents.refresh_counts counts={@counts} />
    </p>
    """
  end
end
