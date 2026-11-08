defmodule Exdock.ClientLib.Container.RecreatorTest do
  use ExUnit.Case, async: true

  alias DockerEngineAPI.Model
  alias Exdock.ClientLib.Container.Recreator
  alias Exdock.ClientLib.Container.Recreator.{Compensation, NetworkSteps, Plan}
  alias Exdock.ClientLib.Container.RecreatorTest.RollbackFailOps
  alias Exdock.ContainerRecreatorFakeOps, as: FakeOps
  alias Exdock.Docker.Error

  @rollback_failures [
    {:stop, "original-id"},
    {:rename, "original-id", "app-exdock-old-original-id"},
    {:disconnect, "original-id", "frontend"},
    :create,
    {:inspect, "new-id"},
    {:disconnect, "new-id", "bridge"},
    {:connect, "new-id", "frontend"},
    {:start, "new-id"}
  ]

  for failure <- @rollback_failures do
    @failure failure

    test "restores the original container when #{inspect(failure)} fails" do
      agent = start_fake_ops(@failure)

      assert {:error, %Error{cause: :injected_failure} = error} =
               Recreator.recreate(agent, "original-id", :container_recreate, nil, FakeOps)

      assert Error.message(error) =~ "injected_failure"

      state = Agent.get(agent, & &1)
      assert state.original.name == "app"
      assert state.original.running
      assert state.original.networks == MapSet.new(["frontend"])
      assert state.replacement == nil
    end
  end

  for failure <- @rollback_failures, mode <- [:raise, :exit] do
    @failure failure
    @mode mode

    test "restores the original when #{inspect(failure)} #{@mode}s" do
      agent = start_fake_ops(@failure)
      Agent.update(agent, &Map.put(&1, :failure_mode, @mode))

      assert {:error, %Error{}} = Recreator.recreate(agent, "original-id", :container_recreate, nil, FakeOps)

      state = Agent.get(agent, & &1)
      assert state.original.name == "app"
      assert state.original.running
      assert state.original.networks == MapSet.new(["frontend"])
      assert state.replacement == nil
    end
  end

  test "rejects auto-removing containers before any destructive operation" do
    agent = start_fake_ops(nil)

    Agent.update(agent, fn state ->
      inspect = %{state.original_inspect | HostConfig: %Model.HostConfig{AutoRemove: true}}
      %{state | original_inspect: inspect}
    end)

    assert {:error, %Error{operation: :inspect_original, cause: :auto_remove_unsupported}} =
             Recreator.recreate(agent, "original-id", :container_recreate, nil, FakeOps)

    assert Agent.get(agent, & &1.calls) == [{:inspect, "original-id"}]
    assert Agent.get(agent, & &1.original.running)
  end

  test "recreates a digest-pinned image available only under RepoDigests" do
    digest = "registry.example/team/app@sha256:abc"
    agent = start_fake_ops(nil, image_reference: digest, image_tags: [])
    Agent.update(agent, &Map.put(&1, :image_digests, [digest]))

    assert {:ok, "new-id"} = Recreator.recreate(agent, "original-id", :container_recreate, nil, FakeOps)
    assert Agent.get(agent, & &1.create_request."Image") == digest
  end

  test "does not stop the original when the requested digest is unavailable" do
    agent = start_fake_ops(nil, image_reference: "app@sha256:missing")

    assert {:error, %Error{operation: :image_unavailable}} =
             Recreator.recreate(agent, "original-id", :container_recreate, nil, FakeOps)

    assert Agent.get(agent, & &1.original.running)
    refute Enum.member?(Agent.get(agent, & &1.calls), {:stop, "original-id"})
  end

  test "pins image-declared and destination-only anonymous volumes to their existing IDs" do
    for binds <- [nil, ["/data:ro"]] do
      inspect = %{
        original_inspect("app:latest")
        | Config: %Model.ContainerConfig{Image: "app:latest", Volumes: %{"/data" => %{}}},
          HostConfig: %Model.HostConfig{Binds: binds},
          Mounts: [%Model.MountPoint{Type: "volume", Name: "existing-volume", Destination: "/data", RW: false}]
      }

      assert {:ok, plan} = Plan.build(inspect)

      assert [%Model.Mount{Type: "volume", Source: "existing-volume", Target: "/data", ReadOnly: true}] =
               plan.create_request."HostConfig"."Mounts"

      assert plan.create_request."HostConfig"."Binds" == []
    end
  end

  test "similar bind destinations do not prevent pinning an anonymous volume" do
    for destination <- ["/data2", "/data/nested"] do
      inspect = %{
        original_inspect("app:latest")
        | HostConfig: %Model.HostConfig{Binds: ["/data:ro", "other:#{destination}", "/data:/backup"]},
          Mounts: [%Model.MountPoint{Type: "volume", Name: "existing-data", Destination: "/data", RW: false}]
      }

      assert {:ok, plan} = Plan.build(inspect)
      assert [%Model.Mount{Source: "existing-data", Target: "/data", ReadOnly: true}] = plan.create_request."HostConfig"."Mounts"
      assert plan.create_request."HostConfig"."Binds" == ["other:#{destination}", "/data:/backup"]
    end
  end

  test "recreates using an available image ID without tags or digests" do
    id = "sha256:" <> String.duplicate("a", 64)
    agent = start_fake_ops(nil, image_reference: id, image_tags: [])
    Agent.update(agent, &Map.put(&1, :image_id, id))
    assert {:ok, "new-id"} = Recreator.recreate(agent, "original-id", :container_recreate, nil, FakeOps)
    assert Agent.get(agent, & &1.create_request."Image") == id
  end

  test "preserves transport failures from image inspection before stopping" do
    agent = start_fake_ops(nil)
    Agent.update(agent, &Map.put(&1, :image_response, {:error, :timeout}))

    assert {:error, %Error{operation: :inspect_image, cause: :timeout}} =
             Recreator.recreate(agent, "original-id", :container_recreate, nil, FakeOps)

    assert Agent.get(agent, & &1.original.running)
  end

  test "rejects malformed image inspection before stopping" do
    agent = start_fake_ops(nil)
    Agent.update(agent, &Map.put(&1, :image_response, {:ok, %{}}))

    assert {:error, %Error{operation: :inspect_image, cause: :malformed_response}} =
             Recreator.recreate(agent, "original-id", :container_recreate, nil, FakeOps)

    assert Agent.get(agent, & &1.original.running)
  end

  for {state, reason} <- [
        {%{Status: "running", Health: %{Status: "unhealthy"}}, :replacement_unhealthy},
        {%{Status: "exited"}, :replacement_not_running},
        {%{Status: "running", Health: %{Status: "starting"}}, :readiness_timeout}
      ] do
    @ready_state state
    @reason reason
    test "restores the original when replacement readiness fails with #{@reason}" do
      agent = start_fake_ops(nil)
      Agent.update(agent, &Map.put(&1, :ready_state, @ready_state))

      assert {:error, %Error{operation: :verify_replacement, cause: @reason}} =
               Recreator.recreate(agent, "original-id", :container_recreate, nil, FakeOps,
                 readiness_timeout: 50,
                 readiness_interval: 1
               )

      state = Agent.get(agent, & &1)
      assert state.original.name == "app"
      assert state.original.running
      assert state.original.networks == MapSet.new(["frontend"])
      assert state.replacement == nil
    end
  end

  test "preserves explicit mounts and options while pinning mount-style anonymous volumes" do
    named = %Model.Mount{Type: "volume", Source: "named", Target: "/named"}

    anonymous = %Model.Mount{
      Type: "volume",
      Source: "",
      Target: "/anonymous",
      ReadOnly: true,
      VolumeOptions: %Model.MountVolumeOptions{NoCopy: true}
    }

    bind = "/host:/bind:ro"

    inspect = %{
      original_inspect("app:latest")
      | HostConfig: %Model.HostConfig{Binds: [bind], Mounts: [named, anonymous]},
        Mounts: [
          %Model.MountPoint{Type: "volume", Name: "named", Destination: "/named", RW: true},
          %Model.MountPoint{Type: "volume", Name: "existing", Destination: "/anonymous", RW: false},
          %Model.MountPoint{Type: "volume", Name: "bound", Destination: "/bind", RW: false},
          %Model.MountPoint{Type: "bind", Destination: "/other"}
        ]
    }

    assert {:ok, plan} = Plan.build(inspect)
    assert plan.create_request."HostConfig"."Binds" == [bind]
    assert plan.create_request."HostConfig"."Mounts" == [named, %{anonymous | Source: "existing"}]
  end

  test "commits the replacement after it starts even if old-container cleanup fails" do
    agent = start_fake_ops({:delete, "original-id"})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, %{id: "new-id", warning: warning}} =
                 Recreator.recreate(agent, "original-id", :container_recreate, nil, FakeOps)

        assert warning =~ "was recreated"
        assert warning =~ "app-exdock-old-original-id"
        assert warning =~ "injected_failure"
      end)

    assert log =~ "cleanup"

    state = Agent.get(agent, & &1)
    assert state.original.name == "app-exdock-old-original-id"
    refute state.original.running
    assert state.replacement == %{name: "app", running: true, networks: MapSet.new(["frontend"])}
  end

  test "reports rollback failures without hiding the triggering operation" do
    agent = start_fake_ops({:start, "new-id"})
    Agent.update(agent, &Map.put(&1, :secondary_failure, {:start, "original-id"}))

    assert {:error, %Error{operation: :start_replacement, cause: :injected_failure} = error} =
             Recreator.recreate(agent, "original-id", :container_recreate, nil, RollbackFailOps)

    message = Error.message(error)
    assert message =~ "start_replacement: injected_failure"
    assert message =~ "rollback errors"
    assert message =~ "restart_original: rollback_failure"
  end

  test "adds the latest tag when the registry host contains a port" do
    image_reference = "registry.example:5000/team/app"

    agent =
      start_fake_ops(nil,
        image_reference: image_reference,
        image_tags: ["#{image_reference}:latest"]
      )

    assert {:ok, "new-id"} =
             Recreator.recreate(agent, "original-id", :container_recreate, nil, FakeOps)
  end

  test "builds an immutable recreation plan before making changes" do
    image_reference = "registry.example:5000/team/app"

    assert {:ok, %Plan{} = plan} =
             Plan.build(original_inspect(image_reference))

    assert plan.original_id == "original-id"
    assert plan.original_name == "app"
    assert plan.temporary_name == "app-exdock-old-original-id"
    assert plan.original_running
    assert plan.image_tag == "#{image_reference}:latest"
    assert plan.create_request."Image" == image_reference
  end

  test "rejects malformed inspect responses while planning" do
    assert {:error, :malformed_response} = Plan.build(%{})
  end

  test "describes network phases as operations with explicit state effects" do
    assert {:ok, %Plan{} = plan} = Plan.build(original_inspect("app:latest"))

    assert [
             {
               {:disconnect_original_network, "frontend"},
               {:disconnect, "original-id", "frontend", %Model.NetworkDisconnectRequest{}},
               {:record_detachment, "frontend", %Model.EndpointSettings{}}
             }
           ] = NetworkSteps.disconnect_original(plan)

    assert [
             {
               {:connect_replacement_network, "frontend"},
               {:connect, "new-id", "frontend", %Model.NetworkConnectRequest{}},
               :unchanged
             }
           ] = NetworkSteps.connect_replacement(plan, "new-id")
  end

  test "runs every compensation and reports failures in execution order" do
    owner = self()

    execute = fn
      :first ->
        send(owner, :first)
        {:error, :first_failed}

      :successful ->
        send(owner, :successful)
        {:ok, :restored}

      :last ->
        send(owner, :last)
        raise "last failed"
    end

    errors =
      Compensation.run(
        [
          {:first, :first},
          {:successful, :successful},
          {:last, :last}
        ],
        execute
      )

    assert_receive :first
    assert_receive :successful
    assert_receive :last

    assert [
             {:first, :first_failed},
             {:last, %RuntimeError{message: "last failed"}}
           ] = errors
  end

  defp start_fake_ops(fail_at, opts \\ []) do
    image_reference = Keyword.get(opts, :image_reference, "app:latest")
    image_tags = Keyword.get(opts, :image_tags, ["app:latest"])

    start_supervised!({
      Agent,
      fn ->
        %{
          fail_at: fail_at,
          secondary_failure: nil,
          calls: [],
          original_inspect: original_inspect(image_reference),
          new_inspect: replacement_inspect(),
          image_tags: image_tags,
          original: %{name: "app", running: true, networks: MapSet.new(["frontend"])},
          replacement: nil
        }
      end
    })
  end

  defp original_inspect(image_reference) do
    %Model.ContainerInspectResponse{
      Id: "original-id",
      Name: "/app",
      Config: %Model.ContainerConfig{Image: image_reference},
      State: %Model.ContainerState{Status: "running"},
      NetworkSettings: %Model.NetworkSettings{
        Networks: %{"frontend" => %Model.EndpointSettings{Aliases: ["app"]}}
      }
    }
  end

  defp replacement_inspect do
    %Model.ContainerInspectResponse{
      Id: "new-id",
      Name: "/app",
      Config: %Model.ContainerConfig{Image: "app:latest"},
      State: %Model.ContainerState{Status: "created"},
      NetworkSettings: %Model.NetworkSettings{
        Networks: %{"bridge" => %Model.EndpointSettings{}}
      }
    }
  end
end
