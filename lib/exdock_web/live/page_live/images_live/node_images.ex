defmodule ExdockWeb.ImagesLive.NodeImages do
  use ExdockWeb, :live_component
  alias ExdockWeb.PageLive.Utils.IdUtils
  alias Exdock.Size

  @impl true
  def update(%{images: images} = assigns, socket) do
    rows =
      images
      |> Enum.sort(&(&1.tags >= &2.tags))
      |> Enum.map(fn image ->
        %{
          id: IdUtils.create_id("#{assigns.id}-image-#{image.id}"),
          image: image
        }
      end)

    socket =
      socket
      |> assign(Map.drop(assigns, [:images]))
      |> assign(:image_count, length(images))
      |> stream(:images, rows, reset: true)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="overflow-hidden">
      <div class="flex w-full flex-col">
        <header class="flex min-w-0 items-center gap-3 border-b border-secondary pb-3 pr-12">
          <span class="grid size-9 shrink-0 place-items-center rounded-lg border border-secondary bg-secondary text-mid-visibility shadow-sm">
            <.icon name="hero-square-2-stack" class="size-[1.125rem]" />
          </span>

          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <h2 class="font-mono text-base font-bold tracking-tight text-high-visibility">Images</h2>
              <span
                class="rounded-md border border-secondary bg-primary px-1.5 py-0.5 font-mono text-xxs font-bold tabular-nums text-mid-visibility"
                aria-label={"#{@image_count} images"}
              >
                {@image_count}
              </span>
            </div>
            <p class="truncate font-mono text-xs font-medium text-low-visibility" title={@node}>
              {@node}
            </p>
          </div>
        </header>

        <div class="flex w-full py-2.5">
          <.delete_unused info={@info.images.unused} node={@node} />
        </div>

        <div class="flex w-full">
          <ExdockWeb.ImagesLive.ImagesList.render
            id={IdUtils.create_id("images_list#{@id}")}
            nodename={@node}
            images={@streams.images}
          />
        </div>
      </div>
    </div>
    """
  end

  defp delete_unused(assigns) do
    ~H"""
    <div class="flex w-full flex-row flex-wrap items-center gap-2 rounded-lg border border-secondary bg-primary px-2.5 py-2">
      <span class="grid size-7 shrink-0 place-items-center rounded-md bg-amber-500/10 text-warning">
        <.icon name="hero-archive-box" class="size-4" />
      </span>
      <div class="min-w-0 flex-1">
        <p class="font-mono text-xs font-semibold text-high-visibility">Unused images</p>
        <p class="flex items-center gap-2 font-mono text-xxs text-low-visibility">
          <span class="inline-flex items-center gap-1">
            <.icon name="hero-square-2-stack" class="size-3.5" />
            <span class="font-bold tabular-nums text-mid-visibility">{@info.images_count}</span>
          </span>
          <span aria-hidden="true" class="text-low-visibility">·</span>
          <span class="inline-flex items-center gap-1">
            <.icon name="hero-circle-stack" class="size-3.5" />
            <span class="font-bold tabular-nums text-mid-visibility">
              ~{Size.human_readable(@info.total_bytesize - @info.shared_bytesize)}
            </span>
            reclaimable
          </span>
        </p>
      </div>
      <button
        id={IdUtils.create_id("delete-unused-images-#{@node}")}
        class={[
          "inline-flex h-7 shrink-0 items-center gap-1 rounded-md border px-2 font-mono text-xxs font-bold transition-all",
          if(@info.images_count > 0,
            do: "border-red-500/25 bg-red-500/5 text-error-two hover:border-red-500/45 hover:bg-red-500/10",
            else: "cursor-not-allowed border-secondary bg-secondary text-low-visibility opacity-60"
          )
        ]}
        phx-click="image_delete_unused"
        phx-value-node={@node}
        disabled={@info.images_count == 0}
        aria-label={"Delete #{@info.images_count} unused images from #{@node}"}
      >
        <.icon name="hero-trash" class="size-3.5" /> Delete
      </button>
    </div>
    """
  end
end
