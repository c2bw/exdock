defmodule ExdockWeb.Commons.ContainerManager.Configuration.DetailsPanel do
  @moduledoc false

  use ExdockWeb, :html

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  def render(assigns) do
    ~H"""
    <div class="mt-1">
      <details
        class="group rounded border border-primary border-primary-hover bg-primary"
        id={@id}
        phx-hook="CollapsibleState"
      >
        <summary
          class="flex cursor-pointer list-none flex-nowrap items-center justify-between rounded"
          id={@id <> "_summary"}
        >
          <div class="flex w-full justify-start">
            <p class="m-2 ms-3 w-64 truncate text-start font-mono font-semibold text-mid-visibility">
              {@title}
            </p>
          </div>
        </summary>

        {render_slot(@inner_block)}
      </details>
    </div>
    """
  end
end
