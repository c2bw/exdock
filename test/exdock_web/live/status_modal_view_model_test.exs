defmodule ExdockWeb.StatusModalViewModelTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Logging.Status.Dashboard
  alias Exdock.Status.Dashboard.Row
  alias ExdockWeb.PageLive.StatusModal.ViewModel

  test "normalizes node, progress, action, and error groups" do
    dashboard =
      Dashboard.new()
      |> Map.put(:node_refresh, %{
        "node_a" => Row.new({:ok, :requested}, nil),
        "node_b" => Row.new({:error, :nodedown}, nil)
      })
      |> Map.put(:registry_fetch, %{
        "registry-1" => Row.new({:ok, :requested}, %{fetched: 2, total: 3}),
        "registry-2" => Row.new({:ok, :requested}, %{fetched: 1, total: 4})
      })
      |> Map.put(:image_pull, %{
        {:node_a, "example/app:latest"} => Row.new({:ok, :requested}, nil) |> Row.put_message({:string, "Downloading"})
      })

    view_model = ViewModel.build(dashboard, true, [{"now", "failed"}])

    assert %{awaiting?: true, entries: node_entries} = view_model.nodes
    assert %{node: "node_b", state: :error} in node_entries

    assert %{fetched: 3, total: 7, active?: true} =
             Enum.find(view_model.progress, &(&1.title == "Fetch Registry"))

    assert %{actions: actions} = Enum.find(view_model.action_groups, &(&1.title == "Images"))
    assert %{entries: entries} = Enum.find(actions, &(&1.label == "Pull"))

    assert [
             %{
               node: "node_a",
               item: "example/app:latest",
               row: %Row{message: {:string, "Downloading"}}
             }
           ] =
             entries

    assert view_model.has_errors?
    assert view_model.errors_log == [{"now", "failed"}]
  end
end
