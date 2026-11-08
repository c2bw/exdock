defmodule Exdock.Server.Jobs.Local.RegistryTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Jobs
  alias Exdock.Server.Jobs.Local.Registry
  alias Exdock.Server.Jobs.Local.Registry.FetchReport
  alias Exdock.Server.Jobs.Payload.RegistryFetch
  alias Exdock.Server.RegistryFetchLimiter
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage.TagsInfo
  alias Exdock.Server.State.Storage
  alias Exdock.Domain
  alias Exdock.Domain.Container
  alias Regc.Oci.Error

  test "fetch_cluster builds a registry payload for running containers across all nodes" do
    state =
      state_with_containers(%{
        "node1" => [
          container_on_node("node1", "app", true, "registry.example/app:latest"),
          container_on_node("node1", "stopped", false, "registry.example/stopped:latest")
        ],
        "node2" => [
          container_on_node("node2", "app-copy", true, "registry.example/app:latest"),
          container_on_node("node2", "worker", true, "registry.example/worker:latest")
        ]
      })

    assert %Jobs.Detail{name: :registry_fetch, spec_list: [{%Jobs.Spec{} = spec, _id}]} = Registry.fetch_cluster(state)

    assert MapSet.new(spec.data.image_requests) ==
             MapSet.new([
               %{tag: "registry.example/app:latest", platform: "linux/amd64"},
               %{tag: "registry.example/app:latest", platform: "linux/arm64"},
               %{tag: "registry.example/worker:latest", platform: "linux/arm64"}
             ])
  end

  test "fetch_node builds a registry payload for running containers on a single node" do
    state =
      state_with_containers(%{
        "node1" => [container_on_node("node1", "app", true, "registry.example/app:latest")],
        "node2" => [container_on_node("node2", "worker", true, "registry.example/worker:latest")]
      })

    assert %Jobs.Detail{name: :registry_fetch, spec_list: [{%Jobs.Spec{} = spec, _id}]} =
             Registry.fetch_node(state, "node2")

    assert spec.data.image_requests == [
             %{tag: "registry.example/worker:latest", platform: "linux/arm64"}
           ]
  end

  test "fetch_cluster returns no work when no running containers are available" do
    state =
      state_with_containers(%{
        "node1" => [container_on_node("node1", "stopped", false, "registry.example/app:latest")]
      })

    assert Registry.fetch_cluster(state) == nil
  end

  test "running_image_requests/2 groups unique node platforms by running tag" do
    containers = [
      container("app", true, "registry.example/app:latest"),
      container("app-copy", true, "registry.example/app:latest"),
      container_on_node("arm_node", "app-arm", true, "registry.example/app:latest"),
      container_on_node("arm_node", "worker", true, "registry.example/worker:latest"),
      container("stopped", false, "registry.example/stopped:latest")
    ]

    assert Registry.running_image_requests(containers, %{
             "node" => "linux/amd64",
             "arm_node" => "linux/arm64"
           }) == [
             %{
               tag: "registry.example/app:latest",
               platform: "linux/amd64"
             },
             %{tag: "registry.example/app:latest", platform: "linux/arm64"},
             %{tag: "registry.example/worker:latest", platform: "linux/arm64"}
           ]
  end

  test "registry automation skips immutable local image IDs" do
    id = "sha256:" <> String.duplicate("a", 64)

    containers = [
      container("local", true, id),
      container("local-bare", true, String.duplicate("b", 64)),
      container("remote", true, "example/app:latest")
    ]

    assert Registry.running_image_requests(containers, %{"node" => "linux/amd64"}) ==
             [%{tag: "example/app:latest", platform: "linux/amd64"}]
  end

  test "running_image_requests/2 rejects a running container whose node has no platform" do
    assert_raise ArgumentError, ~s(missing registry platform for node "node"), fn ->
      Registry.running_image_requests(
        [container("app", true, "registry.example/app:latest")],
        %{}
      )
    end
  end

  test "running_image_requests/2 appends latest to tagless image references" do
    containers = [
      container("ubooquity", true, "linuxserver/ubooquity"),
      container("ubooquity-copy", true, "linuxserver/ubooquity:latest"),
      container("private", true, "registry.example:5000/team/app")
    ]

    assert Registry.running_image_requests(
             containers,
             %{"node" => "linux/amd64"}
           ) == [
             %{tag: "linuxserver/ubooquity:latest", platform: "linux/amd64"},
             %{
               tag: "registry.example:5000/team/app:latest",
               platform: "linux/amd64"
             }
           ]
  end

  test "build_detail/3 creates a local registry fetch job with platform-aware image data" do
    containers = [
      container("app", true, "registry.example/app:latest"),
      container("stopped", false, "registry.example/stopped:latest")
    ]

    assert %Jobs.Detail{name: :registry_fetch, spec_list: [{%Jobs.Spec{} = spec, _id}]} =
             Registry.build_detail(
               containers,
               %TagsInfo{tags: %{}},
               %{"node" => "linux/amd64"}
             )

    assert %Jobs.Spec.Local{function: function} = spec.location
    assert is_function(function, 2)
    assert spec.parameters == []

    assert spec.data ==
             RegistryFetch.new([
               %{tag: "registry.example/app:latest", platform: "linux/amd64"}
             ])
  end

  test "build_detail/3 returns nil when there are no running container tags" do
    assert Registry.build_detail(
             [container("stopped", false, "registry.example/stopped:latest")],
             %TagsInfo{tags: %{}},
             %{}
           ) == nil
  end

  test "fetch_tag/6 publishes a detailed error update when a registry lookup fails" do
    image_tag = "registry.example/missing:latest"
    job_id = "registry-job"
    owner = self()

    assert {:error, %RuntimeError{message: "registry unavailable"},
            %Domain.TagInfo{
              tag: ^image_tag,
              platform: "linux/amd64",
              latest_digest: "",
              check_date: %DateTime{}
            }} =
             Registry.fetch_tag(
               image_tag,
               "linux/amd64",
               nil,
               job_id,
               fn ^image_tag, "linux/amd64", nil ->
                 raise "registry unavailable"
               end,
               &send(owner, {:registry_update, &1})
             )

    assert_receive {:registry_update,
                    %Jobs.Update{
                      id: ^job_id,
                      update: ^image_tag,
                      remove_node: false,
                      error: %RuntimeError{message: "registry unavailable"}
                    }}
  end

  test "failed registry metadata produces an errored image status instead of unknown" do
    image_tag = "registry.example/missing:latest"

    failed_result =
      Registry.fetch_tag(
        image_tag,
        "linux/amd64",
        nil,
        "registry-job",
        fn _image_tag, _platform, _previous -> raise "registry unavailable" end,
        fn _update -> :ok end
      )

    assert {:error, _error, %Domain.TagInfo{}} = failed_result

    assert %FetchReport{
             tags: [%Domain.TagInfo{} = tag_info],
             request_failures: [%{reason: %RuntimeError{message: "registry unavailable"}}],
             worker_exits: []
           } = Registry.collect_remote_report([{:ok, failed_result}])

    image = %Domain.Image{
      size: 1,
      digest: "sha256:local",
      build_date: DateTime.utc_now(),
      metadata: %Domain.Image.Metadata{}
    }

    assert %Container.Core.ImageData{status: :empty_remote_digest} =
             Container.Core.ImageData.new(tag_info, image, false)
  end

  test "collect_remote_report keeps partial metadata and reports task exits" do
    result =
      {:error, :registry_unavailable,
       %Domain.TagInfo{
         tag: "registry.example/app:latest",
         platform: "linux/amd64"
       }}

    assert %FetchReport{
             tags: [%Domain.TagInfo{}],
             request_failures: [%{reason: :registry_unavailable}],
             worker_exits: [{:task_exit, :killed}]
           } =
             Registry.collect_remote_report([
               {:ok, result},
               {:exit, :killed}
             ])
  end

  test "malformed registry references retain the failed image result" do
    limiter = start_supervised!({RegistryFetchLimiter, name: nil})
    image_tag = "registry..example/team/app:latest"

    assert {:error, %Error{code: :invalid_reference},
            %Domain.TagInfo{
              tag: ^image_tag,
              platform: "linux/amd64",
              latest_digest: "",
              check_date: %DateTime{}
            }} =
             Registry.fetch_tag(
               image_tag,
               "linux/amd64",
               nil,
               "registry-job",
               fn image_tag, _platform, _previous ->
                 RegistryFetchLimiter.run(image_tag, fn -> flunk("fetch should not run") end, limiter)
               end,
               fn _update -> :ok end
             )
  end

  defp state_with_containers(node_map) when is_map(node_map) do
    storage =
      Enum.reduce(Map.to_list(node_map), Storage.Cluster.new().storage, fn {node, node_containers}, acc ->
        node_data =
          node
          |> Domain.Node.default()
          |> Domain.Node.put_metadata(%{"platform" => test_platform(node)})

        acc
        |> Storage.Nodes.set(node, node_data)
        |> Storage.Containers.set_node(node, node_containers)
      end)

    %State{
      cluster: %Storage.Cluster{storage: storage},
      tags: %TagsInfo{tags: %{}}
    }
  end

  defp test_platform("node2"), do: "linux/arm64"
  defp test_platform(_node), do: "linux/amd64"

  defp container(name, running?, tag) do
    %Container{
      node: "node",
      name: name,
      id: "container-#{name}",
      core: %Container.Core{
        is_running: running?,
        image_data: %Container.Core.ImageData{tag_info: %Domain.TagInfo{tag: tag}}
      }
    }
  end

  defp container_on_node(node, name, running?, tag) when is_binary(node) and is_binary(name) do
    %Container{
      node: node,
      name: "container-#{name}",
      id: "container-#{node}-#{name}",
      core: %Container.Core{
        is_running: running?,
        image_data: %Container.Core.ImageData{tag_info: %Domain.TagInfo{tag: tag}}
      }
    }
  end
end
