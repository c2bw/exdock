defmodule ExdockWeb.Commons.ContainerManager.Configuration.Logs do
  @moduledoc false

  use ExdockWeb, :html

  alias Exdock.Datetime
  alias ExdockWeb.Commons.ContainerManager.Configuration.DetailsPanel
  alias ExdockWeb.Commons.ContainerManager.LogFormatter

  attr :id, :string, required: true
  attr :logs, :any, default: nil
  attr :form, :any, required: true

  def render(assigns) do
    ~H"""
    <DetailsPanel.render id={@id <> "logs_details"} title="Logs">
      <div class="flex flex-col rounded border border-tertiary bg-primary">
        <div class="my-2 flex w-full flex-row">
          <div class="mt-1 flex w-full justify-start">
            <p
              :if={@logs != nil and @logs.time != nil}
              class="ms-3 whitespace-nowrap font-mono text-xs text-mid-visibility"
            >
              Last fetch:
              <span class="font-mono">
                {@logs.time |> Datetime.utc_to_timezone() |> Datetime.prettify(:millisecond)}
              </span>
            </p>
          </div>

          <div class="mt-0 flex w-full justify-end">
            <.form for={@form} id={@id <> "-logs-form"} phx-submit="container-logs">
              <.input
                type="hidden"
                field={@form[:node]}
                id={@id <> "fetch_logs_node"}
              />
              <.input
                type="hidden"
                field={@form[:container_name]}
                id={@id <> "fetch_logs_container"}
              />
              <button class="btn-tertiary me-6 mb-0 ms-0 flex h-6 flex-row flex-nowrap px-2 py-0">
                <div class="mt-1 flex">
                  <.icon name="hero-bars-arrow-up" class="mr-0 mb-0 h-5 w-5" />
                </div>

                <div class="flex">
                  <p class="ms-0.5 max-md:hidden">Fetch</p>
                </div>
              </button>
            </.form>
          </div>
        </div>

        <div class="flex w-full">
          <div class="mx-3 mt-0 max-h-96 w-full overflow-auto border-t border-primary pt-1">
            <ul :if={@logs} class="flex flex-col space-y-1 text-xs text-mid-visibility">
              <li :for={line <- @logs.lines} class="ms-1">
                <pre class="text-start">{LogFormatter.format(line)}</pre>
              </li>
            </ul>

            <p :if={is_nil(@logs)} class="py-2 text-center text-xs text-mid-visibility">
              No logs
            </p>
          </div>
        </div>
      </div>
    </DetailsPanel.render>
    """
  end
end
