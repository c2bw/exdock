defmodule Exdock.ClientLib.JobsTest do
  use ExUnit.Case, async: true

  alias Exdock.ClientLib.Jobs
  alias Exdock.ClientLib.Jobs.Context
  alias Exdock.Docker.Error
  alias Exdock.TestSupport.DockerEngineFake

  setup do
    DockerEngineFake.register_owner(self())
    %{context: Context.new(DockerEngineFake)}
  end

  test "node refresh orchestrates through the configured engine adapter", %{context: context} do
    assert {:ok, {%{ok: [], errored: []}, %{ok: [], errored: []}}} =
             Jobs.node_refresh("refresh-id", [retrieve_resources: true], context)

    assert_receive {:docker_engine, :connect}
    assert_receive {:docker_engine, {:list_containers, true, [status: :all]}}
    assert_receive {:docker_engine, :list_images}
  end

  test "node refresh does not fetch images after a container-list failure", %{context: context} do
    DockerEngineFake.put_result(:list_containers, {:error, "container list unavailable"})

    assert {:error,
            %Error{
              operation: :container_list,
              cause: "container list unavailable",
              message: "container list unavailable"
            }, {%{ok: [], errored: []}, %{ok: [], errored: []}}} =
             Jobs.node_refresh("refresh-id", [retrieve_resources: false], context)

    assert_receive {:docker_engine, :connect}
    assert_receive {:docker_engine, {:list_containers, false, [status: :all]}}
    refute_receive {:docker_engine, :list_images}
  end

  test "container commands do not depend on generated connection types", %{context: context} do
    assert {:ok, "container-id"} = Jobs.container_start("job-id", "container-id", context)

    assert_receive {:docker_engine, :connect}
    assert_receive {:docker_engine, {:start_container, "container-id"}}
  end

  test "restart uses a single native operation without a destructive stop", %{context: context} do
    assert {:ok, "app"} = Jobs.container_restart(nil, "app", context)
    assert_receive {:docker_engine, {:restart_container, "app"}}
    refute_receive {:docker_engine, {:stop_container, _}}, 0
    refute_receive {:docker_engine, {:start_container, _}}, 0
    DockerEngineFake.put_result(:restart_container, {:error, :timeout})
    assert {:error, %Error{operation: :container_restart, cause: :timeout}, "app"} = Jobs.container_restart(nil, "app", context)
  end

  test "simple Docker actions share success normalization", %{context: context} do
    actions = [
      {:start_container, fn -> Jobs.container_start("job-id", "container-id", context) end, {:start_container, "container-id"},
       "container-id"},
      {:stop_container, fn -> Jobs.container_stop("job-id", "container-id", context) end, {:stop_container, "container-id"},
       "container-id"},
      {:delete_image, fn -> Jobs.image_delete("job-id", "image-id", context) end, {:delete_image, "image-id"}, "image-id"},
      {:pull_image, fn -> Jobs.image_pull("job-id", "example/app:latest", context) end,
       {:pull_image, "example/app:latest", true, :image_pull, "job-id"}, "example/app:latest"}
    ]

    for {operation, run, expected_call, identifier} <- actions do
      DockerEngineFake.put_result(operation, {:ok, :done})
      assert {:ok, ^identifier} = run.()
      assert_receive {:docker_engine, :connect}
      assert_receive {:docker_engine, ^expected_call}
    end
  end

  test "simple Docker actions share error normalization", %{context: context} do
    actions = [
      {:start_container, :container_start, fn -> Jobs.container_start("job-id", "container-id", context) end, "container-id"},
      {:stop_container, :container_stop, fn -> Jobs.container_stop("job-id", "container-id", context) end, "container-id"},
      {:delete_image, :image_delete, fn -> Jobs.image_delete("job-id", "image-id", context) end, "image-id"},
      {:pull_image, :image_pull, fn -> Jobs.image_pull("job-id", "example/app:latest", context) end, "example/app:latest"}
    ]

    for {operation, error_operation, run, identifier} <- actions do
      DockerEngineFake.put_result(operation, {:error, "docker unavailable"})

      assert {:error,
              %Error{
                operation: ^error_operation,
                cause: "docker unavailable",
                message: "docker unavailable"
              }, ^identifier} = run.()

      assert_receive {:docker_engine, :connect}
      assert_receive {:docker_engine, _operation}
    end
  end

  test "container recreation delegates its workflow through the container domain", %{context: context} do
    DockerEngineFake.put_result(:recreate_container, {:ok, "replacement-id"})

    assert {:ok, "container-id"} =
             Jobs.container_recreate("job-id", "container-id", false, context)

    assert_receive {:docker_engine, :connect}

    assert_receive {:docker_engine, {:recreate_container, "container-id", :container_recreate, "job-id"}}

    refute_receive {:docker_engine, {:container_image_info, "container-id"}}
  end

  test "recreation cleanup warnings cross the wire as successful terminal results", %{context: context} do
    warning = "Recreated app, but cleanup of app-exdock-old-123 failed: permission denied"
    DockerEngineFake.put_result(:recreate_container, {:ok, %{id: "replacement-id", warning: warning}})
    assert {:ok, data} = Jobs.container_recreate("job-id", "app", false, context)
    assert data == %{"container" => "app", "warning" => warning}

    payload = Exdock.Protocol.Message.result("job-id", "container_recreate", "node-a", data, nil)
    frame = Exdock.Protocol.Contract.encode_term_frame(:result, payload)

    assert {:client_message, %Exdock.Server.Connection.WireMessage{data: ^data, error: nil}} =
             Exdock.Server.Connection.Protocol.decode_message(frame, :authenticated)
  end

  test "container logs apply defaults and resources preserve the container id", %{context: context} do
    DockerEngineFake.put_result(:container_logs, {:ok, ["line"]})
    DockerEngineFake.put_result(:container_resources, {:ok, %{memory: 42}})

    assert {:ok, {"container-id", ["line"]}} =
             Jobs.container_logs("job-id", "container-id", [tail: 10], context)

    assert_receive {:docker_engine, :connect}

    assert_receive {:docker_engine, {:container_logs, "container-id", [stderr: true, stdout: true, tail: 10]}}

    assert {:ok, {"container-id", %{memory: 42}}} =
             Jobs.container_resources("job-id", "container-id", context)

    assert_receive {:docker_engine, :connect}
    assert_receive {:docker_engine, {:container_resources, "container-id"}}
  end
end
