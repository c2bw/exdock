defmodule ExdockWeb.Commons.ContainerManager.Configuration do
  @moduledoc false

  use ExdockWeb, :html

  alias ExdockWeb.Commons.ContainerManager.Configuration.{
    Logs,
    RawInspect,
    Table
  }

  attr :id, :string, required: true
  attr :core, :any, required: true
  attr :extended, :any, required: true
  attr :logs_form, :any, required: true
  attr :nodename, :string, required: true
  attr :container_name, :string, required: true
  attr :clock_now, :any, required: true

  def render(assigns) do
    ~H"""
    <div>
      <Table.render id={@id <> "-table"} core={@core} clock_now={@clock_now} />
      <RawInspect.render
        id={@id <> "raw_inspect_details"}
        compressed_inspect={@core.json_compressed_inspect}
      />
      <Logs.render id={@id} logs={@extended.logs} form={@logs_form} />
    </div>
    """
  end
end
