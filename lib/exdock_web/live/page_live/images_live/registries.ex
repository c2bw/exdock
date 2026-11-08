defmodule ExdockWeb.ImagesLive.Registries do
  use ExdockWeb, :html
  attr :id, :string, required: true
  attr :registries, :list, required: true

  def render(assigns) do
    ~H"""
    <div class="flex flex-col space-y-4">
      <div class="flex">
        <p class="text-mid-visibility text-sm font-mono">
          Registries [{Enum.count(@registries)}]
        </p>
      </div>

      <div class="space-y-2 w-full min-w-fit border border-tertiary rounded py-1 bg-primary">
        <table class="m-0 table-auto text-center w-full font-mono bg-primary">
          <thead class="divide-y divide-tertiary whitespace-nowrap">
            <tr class="text-left leading-0 text-high-visibility pt-1">
              <td class="ps-2 pe-2 text-low-visibility text-xs text-start truncate">Registry</td>

              <td class="ps-0 pe-2 text-low-visibility text-xs text-start truncate">Images</td>
            </tr>
          </thead>

          <tbody class="first-row-divider-subtle divide-y divide-primary whitespace-nowrap">
            <%= for {provider,count} <- @registries do %>
              <tr class="text-sm text-left leading-6 text-high-visibility pb-2 bg-hover-tertiary">
                <td class="ps-2 pe-2 text-xs">{provider}</td>

                <td class="ps-2 pe-2 text-xs">{count}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
