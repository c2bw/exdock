defmodule ExdockWeb.Commons.ContainerManager.Configuration.RawInspect do
  @moduledoc false

  use ExdockWeb, :html

  alias ExdockWeb.Commons.ContainerManager.Configuration.DetailsPanel

  attr :id, :string, required: true
  attr :compressed_inspect, :any, required: true

  def render(assigns) do
    ~H"""
    <DetailsPanel.render id={@id} title="Raw Jason">
      <div class="mx-2 ms-3 max-h-96 overflow-auto border-t border-primary pt-2">
        <pre class="whitespace-pre-wrap text-start font-mono text-xs text-mid-visibility">{:zlib.gunzip(@compressed_inspect)}</pre>
      </div>
    </DetailsPanel.render>
    """
  end
end
