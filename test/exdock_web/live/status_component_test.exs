defmodule ExdockWeb.StatusComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Exdock.Server.Logging.Status
  alias ExdockWeb.PageLive.Status, as: StatusComponent

  test "renders active work with a visible blue status accent" do
    status =
      Status.new()
      |> Map.put(:jobs, %{{:node_refresh, "job-1"} => %{}})
      |> Map.put(:latest_job, "Refresh")
      |> Map.put(:latest_job_message, "Refreshing nodes")

    document =
      render_component(&StatusComponent.render/1, %{id: "status-component", status: status})
      |> LazyHTML.from_fragment()

    assert LazyHTML.filter(document, "#cluster-status-button[data-status='working'] .text-blue-700") != []
    assert LazyHTML.filter(document, "#cluster-status-button[data-status='working'] .bg-blue-500") != []
  end
end
