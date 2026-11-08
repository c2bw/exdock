defmodule ExdockWeb.Commons.ContainerManager.InfoMessages do
  use Phoenix.Component
  attr :messages, :list, required: true

  def render(assigns) do
    ~H"""
    <%= if @messages != [] do %>
      <div class="mb-3 rounded-lg border border-primary bg-primary-lighter p-3">
        <div class="flex flex-row">
          <ul class="text-xs text-start text-low-visibility flex flex-col space-y-1">
            <%= for message <- @messages do %>
              <li class="hover:break-all">
                <%= case message do %>
                  <% {:stack, stack_name} -> %>
                    <p class="ms-1">
                      This container is part of a <span class="text-mid-visibility">stack</span>
                      [<span class="text-mid-visibility">{stack_name}</span>], consider the use of <span class="text-mid-visibility">docker-compose</span>.
                    </p>
                  <% :recreate_disabled -> %>
                    <p class="ms-1">
                      <span class="text-mid-visibility">Recreate</span>
                      is <span class="text-mid-visibility">disabled</span>
                      for Exdock containers.
                    </p>
                <% end %>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
    <% end %>
    """
  end
end
