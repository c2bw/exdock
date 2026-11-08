defmodule ExdockWeb.ImagesLive.ImagesList do
  use ExdockWeb, :html
  alias Exdock.Size

  attr :id, :string, required: true
  attr :nodename, :any, required: true
  attr :images, :any, required: true

  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="grow max-h-[48rem] overflow-auto rounded-lg border border-tertiary bg-see-through shadow-inner"
    >
      <table class="m-0 w-full min-w-[60rem] table-auto text-left font-mono">
        <thead class="sticky top-0 z-10 border-b border-secondary bg-primary-lighter text-xxs font-bold uppercase leading-6 tracking-wider text-low-visibility shadow-sm">
          <tr>
            <th class="w-[5.25rem] border-r border-secondary px-2 py-0.5">
              <span class="sr-only">Delete image</span>
            </th>
            <th class="w-10 border-r border-secondary px-1 py-0.5 text-center">
              <span class="sr-only">Deletion lock</span>
              <.icon name="hero-lock-closed" class="size-3.5" />
            </th>
            <th class="px-2 py-0.5">Tags</th>
            <th class="w-20 px-2 py-0.5 text-center">Usage</th>
            <th class="w-40 px-2 py-0.5">Built</th>
            <th class="w-20 px-2 py-0.5 text-right">Size</th>
            <th class="w-24 px-2 py-0.5 text-right">Reclaimable</th>
            <th class="w-44 px-2 py-0.5">Image ID</th>
          </tr>
        </thead>

        <tbody
          id={"#{@id}-stream"}
          phx-update="stream"
          class="first-row-divider-subtle divide-y divide-primary whitespace-nowrap"
        >
          <%= for {id, row} <- @images do %>
            <.image_row id={id} image={row.image} nodename={@nodename} />
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp image_row(assigns) do
    ~H"""
    <tr
      id={@id}
      class="images-list-row group text-left text-xs leading-7 text-high-visibility transition-colors"
    >
      <td class="w-[5.25rem] border-r border-primary px-1.5">
        <%= if not image_in_use?(@image) do %>
          <%= if not image_delete_lock?(@image) do %>
            <button
              id={"#{@id}-delete"}
              phx-click="image_delete"
              phx-value-nodename={@nodename}
              phx-value-imageid={@image.id}
              phx-value-imagetags={@image.tags}
              class="inline-flex h-6 w-full items-center justify-center gap-0.5 rounded-md border border-transparent px-1 font-mono text-xxs font-bold text-error-two transition-colors hover:border-red-500/30 hover:bg-red-500/10"
              aria-label={"Delete image #{image_tags(@image)}"}
            >
              <.icon name="hero-trash" class="size-3.5" />Delete
            </button>
          <% else %>
            <button
              id={"#{@id}-delete"}
              phx-click="image_delete"
              phx-value-nodename={@nodename}
              phx-value-imageid={@image.id}
              phx-value-imagetags={@image.tags}
              class="inline-flex h-6 w-full cursor-not-allowed items-center justify-center gap-0.5 rounded-md border border-secondary bg-secondary px-1 font-mono text-xxs font-bold text-low-visibility opacity-60"
              disabled
              aria-label={"Image #{image_tags(@image)} is locked and cannot be deleted"}
            >
              <.icon name="hero-trash" class="size-3.5" />Delete
            </button>
          <% end %>
        <% else %>
          <span class="block text-center text-low-visibility" aria-label="Image is in use">—</span>
        <% end %>
      </td>

      <td class="w-10 border-r border-primary px-1 text-center">
        <%= if not image_delete_lock?(@image) do %>
          <button
            id={"#{@id}-lock"}
            phx-click="image_delete_lock"
            phx-value-nodename={@nodename}
            phx-value-imageid={@image.id}
            phx-value-tolock="true"
            class="image-lock-button inline-grid size-6 place-items-center rounded-md text-low-visibility transition-colors"
            aria-label={"Protect image #{image_tags(@image)} from deletion"}
            title="Protect from deletion"
          >
            <.icon name="hero-lock-open" class="size-4" />
          </button>
        <% else %>
          <button
            id={"#{@id}-lock"}
            phx-click="image_delete_lock"
            phx-value-nodename={@nodename}
            phx-value-imageid={@image.id}
            phx-value-tolock="false"
            class="image-lock-button inline-grid size-6 place-items-center rounded-md bg-[var(--accent-soft)] text-eye transition-colors"
            aria-label={"Allow image #{image_tags(@image)} to be deleted"}
            title="Allow deletion"
          >
            <.icon name="hero-lock-closed" class="size-4" />
          </button>
        <% end %>
      </td>

      <td class="max-w-72 px-2 tracking-tight">
        <span class="block truncate font-semibold" title={image_tags(@image)}>
          {image_tags(@image)}
        </span>
      </td>

      <td class="w-20 px-2 text-center">
        <%= if image_in_use?(@image) do %>
          <span class="inline-flex rounded-full bg-emerald-500/10 px-1.5 py-0.5 text-xxs font-bold text-container-updated">
            In use
          </span>
        <% else %>
          <span class="inline-flex rounded-full bg-amber-500/10 px-1.5 py-0.5 text-xxs font-bold text-warning">
            Unused
          </span>
        <% end %>
      </td>

      <td class="w-40 px-2 text-xxs tabular-nums text-mid-visibility">
        <time datetime={DateTime.to_iso8601(@image.build_date)}>{format_build_date(@image.build_date)}</time>
      </td>
      <td class="w-20 px-2 text-right font-bold tabular-nums">{@image.size_human}</td>
      <td class="w-24 px-2 text-right font-bold tabular-nums text-mid-visibility">
        {reclaimable_space(@image.size, @image.shared_size)}
      </td>
      <td class="w-44 px-2">
        <span class="block max-w-44 truncate text-xxs tracking-tight text-low-visibility" title={@image.id}>
          {@image.id}
        </span>
      </td>
    </tr>
    """
  end

  defp image_tags(%{tags: []}), do: "untagged"
  defp image_tags(%{tags: tags}) when is_list(tags), do: Enum.join(tags, ", ")
  defp image_tags(%{tags: tags}) when is_binary(tags), do: tags
  defp image_tags(_image), do: "untagged"

  defp format_build_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  defp format_build_date(datetime), do: to_string(datetime)

  defp reclaimable_space(total, total), do: "-"
  defp reclaimable_space(total, shared), do: Size.human_readable(total - shared)

  defp image_delete_lock?(%{delete_lock: lock}) when is_boolean(lock), do: lock
  defp image_delete_lock?(%{settings: %{delete_lock: lock}}) when is_boolean(lock), do: lock
  defp image_delete_lock?(_), do: false

  defp image_in_use?(%{in_use: in_use}) when is_boolean(in_use), do: in_use
  defp image_in_use?(_), do: false
end
