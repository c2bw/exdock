defmodule Exdock.Server.Jobs.Client.ContainerTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Client.Container, as: ContainerJobs
  alias Exdock.Server.Jobs.Payload.ContainerAction
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage
  alias Exdock.Domain.Container
  alias Exdock.Domain.TagInfo

  test "builds a remote detail for an existing container action" do
    detail = ContainerJobs.start(state_with_container("app"), "node", "app")

    assert %Jobs.Detail{name: :container_start, spec_list: [{%Jobs.Spec{} = spec, _id}]} = detail
    assert %Jobs.Spec.Remote{nodes: ["node"]} = spec.location
    assert spec.parameters == ["app"]
    assert spec.data == ContainerAction.new("node", "app")
  end

  test "returns no work when the container is not in the snapshot" do
    assert ContainerJobs.stop(state_with_container("app"), "node", "missing") == nil
  end

  test "logs action uses the container id and keeps empty log options in the remote parameters" do
    detail = ContainerJobs.logs(state_with_container("app"), "node", "app")

    assert %Jobs.Detail{name: :container_logs, spec_list: [{%Jobs.Spec{} = spec, _id}]} = detail
    assert spec.parameters == ["id-app", []]
    assert spec.data == ContainerAction.new("node", "app")
  end

  test "recreate skips missing and blacklisted containers" do
    work =
      state_with_containers(["app", "Exdock-sidecar"])
      |> ContainerJobs.recreate([{"node", "missing"}, {"node", "Exdock-sidecar"}], false)

    assert work == nil
  end

  test "recreate cannot dispatch work for lowercase or labelled control-plane containers" do
    state = state_with_containers(["exdock-server-1", "server"])
    container = Storage.Containers.get_container(state.cluster.storage, "node", "server", :name)
    core = %{container.core | configuration: %Container.Configuration{labels: %{"exdock.protected" => "true"}}}
    storage = Storage.Containers.set_container(state.cluster.storage, "node", %{container | core: core})
    state = %{state | cluster: %{state.cluster | storage: storage}}
    assert ContainerJobs.recreate(state, [{"node", "exdock-server-1"}, {"node", "server"}], true) == nil
  end

  test "recreate returns a single detail for one eligible container" do
    detail =
      state_with_container("app")
      |> ContainerJobs.recreate([{"node", "app"}], false)

    assert %Jobs.Detail{name: :container_recreate, spec_list: [{%Jobs.Spec{} = spec, _id}]} = detail
    assert %Jobs.Spec.Remote{nodes: ["node"]} = spec.location
    assert spec.parameters == ["app", false]
    assert spec.data == ContainerAction.new("node", "app")
  end

  test "recreate with pull returns a pull detail followed by a chained recreate" do
    work =
      state_with_container("app")
      |> ContainerJobs.recreate([{"node", "app"}], true)

    assert [%Jobs.Detail{name: :image_pull} = pull, %Jobs.Detail{name: :container_recreate} = recreate] = work

    assert recreate.start == {:finish, pull.id}
    assert recreate.start_requirements == :success
  end

  test "recreate packages several eligible containers with aggregate log data" do
    package =
      state_with_containers(["app", "worker"])
      |> ContainerJobs.recreate([{"node", "app"}, {"node", "worker"}], false)

    assert %Jobs.Package{name: :container_recreate, details: details, log_on_start: {2, ["app", "worker"], false}} =
             package

    assert Enum.map(details, & &1.name) == [:container_recreate, :container_recreate]
  end

  test "recreate with pull packages flattened pull and recreate details" do
    package =
      state_with_containers(["app", "worker"])
      |> ContainerJobs.recreate([{"node", "app"}, {"node", "worker"}], true)

    assert %Jobs.Package{name: :container_recreate, details: details, log_on_start: {2, ["app", "worker"], true}} =
             package

    assert Enum.map(details, & &1.name) == [:image_pull, :container_recreate, :image_pull, :container_recreate]

    details
    |> Enum.chunk_every(2)
    |> Enum.each(fn [%Jobs.Detail{} = pull, %Jobs.Detail{} = recreate] ->
      assert recreate.start == {:finish, pull.id}
      assert recreate.start_requirements == :success
    end)
  end

  defp state_with_container(name) do
    state_with_containers([name])
  end

  defp state_with_containers(names) do
    storage =
      Storage.Cluster.new().storage
      |> Storage.Containers.set_node("node", Enum.map(names, &container/1))

    %State{cluster: %Storage.Cluster{storage: storage}}
  end

  defp container(name) do
    %Container{
      id: "id-#{name}",
      node: "node",
      name: name,
      core: %Container.Core{
        image_data: %Container.Core.ImageData{tag_info: %TagInfo{tag: "repo/#{name}:latest"}}
      }
    }
  end
end
