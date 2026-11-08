defmodule ExdockWeb.HomepageLive.MassContainerManager.ContainerRow do
  use ExdockWeb, :html
  alias ExdockWeb.PageLive.Utils.IdUtils

  attr :id, :string, required: true
  attr :node, :any, required: true
  attr :key, :map, required: true
  attr :core, :map, required: true
  attr :image_present_on_node, :boolean, required: true

  def render(assigns) do
    ~H"""
    <tr
      id={@id}
      class="bg-hover text-left text-[0.6875rem] text-mid-visibility transition-colors hover:cursor-pointer hover:text-high-visibility"
      phx-click={show_lazy_modal("#{IdUtils.container_manager_id(@node, @key.name)}mass")}
    >
      <td class="px-3 py-1.5 text-center">
        <%= if @image_present_on_node do %>
          <.icon name="hero-check-circle" class="h-4 w-4 text-success-icon" />
        <% else %>
          <.icon name="hero-no-symbol" class="h-4 w-4 text-error" />
        <% end %>
      </td>

      <td class="px-3 py-1.5">{@node}</td>

      <td class="px-3 py-1.5 font-semibold text-high-visibility">{@key.name}</td>

      <td class="px-3 py-1.5">{@core.image_tag}</td>

      <td class="px-3 py-1.5 text-right tabular-nums">{@core.image_size_human}</td>
    </tr>
    """
  end
end
