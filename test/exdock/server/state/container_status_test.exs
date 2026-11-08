defmodule Exdock.Server.State.ContainerStatusTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.State.ContainerStatus
  alias Exdock.Domain.Container
  alias Exdock.Domain.Container.Core
  alias Exdock.Domain.Container.Core.ImageData
  alias Exdock.Domain.Container.Settings

  test "reports a new running container without requesting a notification" do
    new_container = container("app", :outdated, true, 4)

    assert [
             %{
               node: "node",
               name: "app",
               priority: 4,
               previous: nil,
               current: :outdated,
               notify?: false
             }
           ] = ContainerStatus.between("node", [], [new_container])
  end

  test "does not report a new stopped container" do
    assert ContainerStatus.between("node", [], [container("app", :outdated, false, 4)]) == []
  end

  test "reports existing status changes with the current priority" do
    before_containers = [container("app", :updated, true, 2)]
    after_containers = [container("app", :outdated, true, 7)]

    assert [
             %{
               priority: 7,
               previous: :updated,
               current: :outdated,
               notify?: true
             }
           ] = ContainerStatus.between("node", before_containers, after_containers)
  end

  test "ignores unchanged status" do
    before_containers = [container("app", :updated, true, 2)]
    after_containers = [container("app", :updated, true, 7)]

    assert ContainerStatus.between("node", before_containers, after_containers) == []
  end

  defp container(name, status, running?, priority) do
    %Container{
      node: "node",
      name: name,
      id: "#{name}-id",
      core: %Core{
        is_running: running?,
        image_data: %ImageData{status: status},
        settings: %Settings{priority: priority}
      }
    }
  end
end
