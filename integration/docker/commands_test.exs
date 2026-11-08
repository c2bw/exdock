defmodule Exdock.DockerTest.CommandsTest do
  use ExUnit.Case, async: false
  alias Exdock.DockerTest.{Driver, Harness}
  alias Harness, as: H

  setup_all do
    start_supervised!({Registry, keys: :unique, name: Exdock.AgentRegistry})
    start_supervised!({Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor})
    %{context: Application.fetch_env!(:exdock, :docker_test_context)}
  end

  for mode <- [:adapter, :release] do
    @mode mode
    describe "#{mode} commands against real Docker" do
      @tag mode: mode
      test "start, stop and restart preserve container identity", %{context: context} do
        name = fixture!(context)
        before = H.inspect!(context, name)
        assert :ok = Driver.command(context, @mode, :stop, name)
        refute H.inspect!(context, name)["State"]["Running"]
        assert :ok = Driver.command(context, @mode, :stop, name)
        assert :ok = Driver.command(context, @mode, :start, name)
        H.ready!(context, name, "a")
        started = H.inspect!(context, name)["State"]["StartedAt"]
        assert :ok = Driver.command(context, @mode, :start, name)
        assert :ok = Driver.command(context, @mode, :restart, name)
        H.ready!(context, name, "a")
        after_restart = H.inspect!(context, name)
        assert after_restart["Id"] == before["Id"]
        assert after_restart["State"]["StartedAt"] != started
        assert_data!(context, name)
      end

      if mode == :release do
        @tag mode: :release
        test "a stop submitted during recreation runs against the replacement", %{context: context} do
          name = fixture!(context, healthcheck: false)
          before = H.inspect!(context, name)
          assert :ok = Driver.recreate_then_stop(context, name)
          current = H.inspect!(context, name)
          assert current["Id"] != before["Id"]
          refute current["State"]["Running"]
          assert :ok = Driver.command(context, :release, :start, name)
          H.ready!(context, name, "a")
          assert_data!(context, name)
        end

        @tag mode: :release
        test "reconnect defers runtime replacement until active recreation finishes", %{context: context} do
          name = fixture!(context, stop_timeout: 35)
          before = H.inspect!(context, name)
          assert {:error, _} = Driver.recreate_across_disconnect(context, name)
          H.ready!(context, name, "a")
          current = H.inspect!(context, name)
          assert current["Id"] != before["Id"]
          assert_preserved!(before, current)
          assert_data!(context, name)
          assert_old_deleted!(context, before["Id"])
          Driver.await_container_snapshot!(context, name, current["Id"])
          assert :ok = Driver.command(context, :release, :restart, name)
          H.ready!(context, name, "a")
        end
      end

      @tag mode: mode
      test "pull changes the local image without replacing a running container", %{context: context} do
        name = fixture!(context)
        before = H.inspect!(context, name)
        publish_new_image!(context)
        assert :ok = Driver.command(context, @mode, :pull, H.tag())
        assert image_id!(context, H.tag()) == image_id!(context, "fixture:b")
        after_pull = H.inspect!(context, name)
        assert after_pull["Id"] == before["Id"]
        assert after_pull["Image"] == before["Image"]
        H.ready!(context, name, "a")
      end

      @tag mode: mode
      test "native restart preserves an auto-removing container and its data", %{context: context} do
        name = fixture!(context, auto_remove: true)
        before = H.inspect!(context, name)
        assert before["HostConfig"]["AutoRemove"]
        assert :ok = Driver.command(context, @mode, :restart, name)
        H.ready!(context, name, "a")
        current = H.inspect!(context, name)
        assert current["Id"] == before["Id"]
        assert current["HostConfig"]["AutoRemove"]
        assert current["State"]["StartedAt"] != before["State"]["StartedAt"]
        assert_data!(context, name)
      end

      for volume <- [:anonymous, :named] do
        @volume volume
        @tag mode: mode
        test "recreate preserves #{@volume} volume data and configuration", %{context: context} do
          name = fixture!(context, volume: @volume)
          before = H.inspect!(context, name)
          assert :ok = Driver.command(context, @mode, :recreate, name)
          H.ready!(context, name, "a")
          after_recreate = H.inspect!(context, name)
          assert after_recreate["Id"] != before["Id"]
          assert after_recreate["Image"] == before["Image"]
          assert_preserved!(before, after_recreate)
          assert_data!(context, name)
          assert_old_deleted!(context, before["Id"])
        end
      end

      @tag mode: mode
      test "update pulls a changed tag and serves the new application version", %{context: context} do
        name = fixture!(context)
        before = H.inspect!(context, name)
        publish_new_image!(context)
        assert :ok = Driver.command(context, @mode, :update, name)
        H.ready!(context, name, "b")
        updated = H.inspect!(context, name)
        assert updated["Id"] != before["Id"]
        assert updated["Image"] == image_id!(context, "fixture:b")
        assert_preserved!(before, updated)
        assert_data!(context, name)
        assert_old_deleted!(context, before["Id"])
      end

      @tag mode: mode
      test "similar bind paths preserve anonymous volume identity and data", %{context: context} do
        name = fixture!(context, volume: :prefix)
        before = H.inspect!(context, name)
        assert :ok = Driver.command(context, @mode, :recreate, name)
        H.ready!(context, name, "a")
        assert_preserved!(before, H.inspect!(context, name))
        assert "/data:/backup" in H.inspect!(context, name)["HostConfig"]["Binds"]
        assert_data!(context, name)
      end

      @tag mode: mode
      test "recreates a container launched by image ID", %{context: context} do
        name = fixture!(context, image: image_id!(context, "fixture:a"))
        before = H.inspect!(context, name)
        assert :ok = Driver.command(context, @mode, :recreate, name)
        H.ready!(context, name, "a")
        recreated = H.inspect!(context, name)
        assert recreated["Id"] != before["Id"]
        assert recreated["Image"] == before["Image"]
        assert_data!(context, name)
      end

      @tag mode: mode
      test "untagged local images remain visible and their containers remain manageable", %{context: context} do
        seed = fixture!(context)
        id = H.docker!(context, ["commit", "--change", "LABEL exdock.test.untagged=#{seed}", seed])
        image = H.inspect!(context, id)
        assert (image["RepoTags"] || []) == []
        assert (image["RepoDigests"] || []) == []

        if @mode == :adapter do
          assert {:ok, {_containers, images}} = Exdock.ClientLib.Jobs.node_refresh("dangling-refresh", retrieve_resources: false)
          assert images.errored == []
          assert Enum.any?(images.ok, &(&1.id == id and &1.tags == [] and &1.repo_digests == []))
        end

        name = fixture!(context, image: id)

        if @mode == :adapter do
          assert {:ok, {containers, images}} = Exdock.ClientLib.Jobs.node_refresh("untagged-refresh", retrieve_resources: false)
          assert images.errored == []
          assert Enum.any?(images.ok, &(&1.id == id and &1.tags == []))
          assert Enum.any?(containers.ok, &(&1.name == name and &1.image_id == id))
        end

        assert :ok = Driver.command(context, @mode, :restart, name)
        H.ready!(context, name, "a")
        assert :ok = Driver.command(context, @mode, :recreate, name)
        H.ready!(context, name, "a")
        assert H.inspect!(context, name)["Image"] == id
        assert_data!(context, name)
        if @mode == :release, do: Driver.await_container_snapshot!(context, name, H.inspect!(context, name)["Id"])
      end

      for failure <- [:unhealthy, :exits] do
        @failure failure
        @tag mode: mode
        test "a replacement that #{@failure} after start rolls back", %{context: context} do
          name = fixture!(context, healthcheck: @failure != :exits)
          before = H.inspect!(context, name)
          H.publish!(context, Atom.to_string(@failure))
          H.docker!(context, ["tag", "fixture:a", H.tag()])
          assert {:error, _} = Driver.command(context, @mode, :update, name)
          H.ready!(context, name, "a")
          restored = H.inspect!(context, name)
          assert restored["Id"] == before["Id"]
          assert_data!(context, name)
          assert H.docker!(context, ["ps", "-a", "--filter", "name=#{name}", "--format", "{{.Names}}"]) == name
        end
      end

      @tag mode: mode
      test "failed pull leaves the original container running", %{context: context} do
        name = fixture!(context)
        before = H.inspect!(context, name)
        # A nonexistent registry reference must fail, even on an HTTP 200 stream.
        assert {:error, _} = Driver.command(context, @mode, :pull, "127.0.0.1:5001/missing:never")
        assert H.inspect!(context, name)["Id"] == before["Id"]
        H.ready!(context, name, "a")
        assert_data!(context, name)
      end

      @tag mode: mode
      test "a failed update pull prevents recreation", %{context: context} do
        name = fixture!(context)
        before = H.inspect!(context, name)

        H.docker!(context, [
          "exec",
          "suite-registry",
          "rm",
          "-rf",
          "/var/lib/registry/docker/registry/v2/repositories/exdock-fixture/_manifests/tags/rolling"
        ])

        assert {:error, _} = Driver.command(context, @mode, :update, name)
        assert H.inspect!(context, name)["Id"] == before["Id"]
        H.ready!(context, name, "a")
        assert_data!(context, name)
      end

      @tag mode: mode
      test "failed replacement start restores the original container", %{context: context} do
        name = fixture!(context)
        before = H.inspect!(context, name)
        H.publish!(context, "broken")
        H.docker!(context, ["tag", "fixture:a", H.tag()])
        assert {:error, _} = Driver.command(context, @mode, :update, name)
        H.ready!(context, name, "a")
        restored = H.inspect!(context, name)
        assert restored["Id"] == before["Id"]
        assert_preserved!(before, restored)
        assert_data!(context, name)
        remaining = H.docker!(context, ["ps", "-a", "--filter", "name=#{name}", "--format", "{{.Names}}"])
        assert remaining == name
      end

      @tag mode: mode
      test "recreates a stopped container without starting it", %{context: context} do
        name = fixture!(context)
        before = H.inspect!(context, name)
        assert :ok = Driver.command(context, @mode, :stop, name)
        assert :ok = Driver.command(context, @mode, :recreate, name)
        recreated = H.inspect!(context, name)
        assert recreated["Id"] != before["Id"]
        refute recreated["State"]["Running"]
        assert :ok = Driver.command(context, @mode, :start, name)
        H.ready!(context, name, "a")
        assert_data!(context, name)
      end

      @tag mode: mode
      test "recreates a host-network container", %{context: context} do
        name = fixture!(context, network: :host)
        before = H.inspect!(context, name)
        assert :ok = Driver.command(context, @mode, :recreate, name)
        H.ready!(context, name, "a")
        recreated = H.inspect!(context, name)
        assert recreated["Id"] != before["Id"]
        assert recreated["HostConfig"]["NetworkMode"] == "host"
        assert_data!(context, name)
      end

      @tag mode: mode
      test "recreation preserves an explicitly published host port", %{context: context} do
        H.publish!(context, "a")
        name = "fixture-port-" <> Base.encode16(:crypto.strong_rand_bytes(5), case: :lower)
        on_exit(fn -> H.remove!(context, name) end)

        H.docker!(context, [
          "run",
          "-d",
          "--name",
          name,
          "--network",
          "suite-net",
          "--restart",
          "unless-stopped",
          "--stop-timeout",
          "1",
          "-p",
          "127.0.0.1:18080:8080",
          H.tag()
        ])

        H.ready!(context, name, "a")
        before = H.inspect!(context, name)
        assert :ok = Driver.command(context, @mode, :recreate, name)
        H.ready!(context, name, "a")
        recreated = H.inspect!(context, name)
        assert recreated["Id"] != before["Id"]
        assert recreated["NetworkSettings"]["Ports"] == before["NetworkSettings"]["Ports"]
        assert recreated["HostConfig"]["RestartPolicy"] == before["HostConfig"]["RestartPolicy"]
      end
    end
  end

  defp fixture!(context, opts \\ []) do
    name = H.create!(context, opts)
    on_exit(fn -> H.remove!(context, name) end)
    name
  end

  defp publish_new_image!(context) do
    H.publish!(context, "b")
    # Restore A locally so the production pull must actually resolve the tag.
    H.docker!(context, ["tag", "fixture:a", H.tag()])
    assert image_id!(context, H.tag()) == image_id!(context, "fixture:a")
  end

  defp image_id!(context, tag), do: H.docker!(context, ["image", "inspect", "--format", "{{.Id}}", tag])

  defp assert_data!(context, name), do: assert(H.docker!(context, ["exec", name, "cat", "/data/sentinel"]) == "preserved")

  defp assert_old_deleted!(context, id) do
    assert {_, status} = H.docker(context, ["inspect", id])
    assert status != 0
  end

  defp assert_preserved!(before, after_recreate) do
    assert after_recreate["Name"] == before["Name"]

    for key <- ["Env", "Cmd", "Labels", "ExposedPorts", "Healthcheck", "StopTimeout"] do
      assert after_recreate["Config"][key] == before["Config"][key]
    end

    assert after_recreate["HostConfig"]["PortBindings"] == before["HostConfig"]["PortBindings"]

    assert get_in(after_recreate, ["NetworkSettings", "Networks", "suite-net", "Aliases"]) ==
             get_in(before, ["NetworkSettings", "Networks", "suite-net", "Aliases"])

    assert volume_name(after_recreate) == volume_name(before)
  end

  defp volume_name(container) do
    container["Mounts"] |> Enum.find(&(&1["Destination"] == "/data")) |> Map.fetch!("Name")
  end
end
