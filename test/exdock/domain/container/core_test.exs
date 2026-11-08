defmodule Exdock.Domain.Container.CoreTest do
  use ExUnit.Case, async: true

  alias DockerEngineAPI.Model
  alias Exdock.AgentRuntime.Wire
  alias Exdock.Protocol.Snapshot, as: ClientLib
  alias Exdock.Domain
  alias Exdock.Domain.Container
  alias Exdock.Domain.Container.Core
  alias Exdock.Domain.Container.Resources
  alias Exdock.Domain.Container.Settings

  test "stores Docker inspect structs as JSON-safe data" do
    inspect = inspect_response()

    client_container = %ClientLib.Container{
      inspect: inspect,
      is_running: true,
      stack_name: "example"
    }

    tag_info =
      Domain.TagInfo.new(
        "example/app:latest",
        "linux/amd64",
        "sha256:digest",
        DateTime.utc_now(),
        DateTime.utc_now()
      )

    image = image()

    core =
      Core.new(
        client_container,
        tag_info,
        image,
        Settings.default(),
        true,
        false,
        DateTime.utc_now()
      )

    decoded =
      core.json_compressed_inspect
      |> :zlib.gunzip()
      |> JSON.decode!()

    assert decoded["Id"] == "container-id"
    assert decoded["Config"]["Image"] == "example/app:latest"
    assert decoded["State"]["Status"] == "running"
    assert %Container.Configuration{} = core.configuration
    assert %Container.Core.State{} = core.state
    assert %{"Status" => "healthy", "FailingStreak" => 0} = core.state.health
    refute Map.has_key?(core.state.health, "Log")
    assert {:ok, _json} = Jason.encode(core.state)
    projected = Exdock.ReadModel.Container.from_domain(%{node: "node", name: "app", id: "id", core: core, extended: nil})

    assert projected.core.image_status == :updated
    assert projected.core.image_tag == "example/app:latest"
    assert projected.core.image_size_human == "1 KB"
    assert projected.core.repository_url == image.metadata.repository_url
  end

  test "preserves previous data when refresh has no resource sample" do
    first =
      Container.from_client(
        "node",
        client_container(resources: nil),
        nil,
        image(),
        tag_info(),
        true,
        DateTime.utc_now()
      )

    refreshed =
      Container.from_client(
        "node",
        client_container(resources: nil),
        first,
        image(),
        tag_info(),
        true,
        DateTime.utc_now()
      )

    assert refreshed.core.settings == first.core.settings
    assert refreshed.extended == first.extended
  end

  test "carries settings forward but only keeps resource history for the same Docker id" do
    first_sample_at = ~U[2026-07-31 12:00:00Z]
    next_sample_at = DateTime.add(first_sample_at, 1, :second)
    replacement_sample_at = DateTime.add(first_sample_at, 2, :second)

    first =
      Container.from_client(
        "node",
        client_container(id: "container-id", resources: stats_response(first_sample_at)),
        nil,
        image(),
        tag_info(),
        true,
        first_sample_at
      )

    settings = %Settings{priority: 5, auto_update: :enabled, labels: ["production"]}

    previous =
      first
      |> Container.set_settings(settings)
      |> Container.set_resources(Resources.Record.new(stats_response(first_sample_at)))

    refreshed =
      Container.from_client(
        "node",
        client_container(id: "container-id", resources: stats_response(next_sample_at)),
        previous,
        image(),
        tag_info(),
        true,
        next_sample_at
      )

    replaced =
      Container.from_client(
        "node",
        client_container(id: "replacement-id", resources: stats_response(replacement_sample_at)),
        previous,
        image(),
        tag_info(),
        true,
        replacement_sample_at
      )

    assert refreshed.core.settings == settings
    assert Enum.map(refreshed.extended.resources.records, & &1.time) == [next_sample_at, first_sample_at]
    assert replaced.core.settings == settings
    assert replaced.extended.resources.records == []
  end

  test "builds core data from a protocol-owned inspect map" do
    client_container = client_container(resources: nil)

    wire_data =
      Wire.encode_result(
        "node_refresh",
        {%{ok: [client_container], errored: []}, %{ok: [], errored: []}}
      )

    [encoded_container] = wire_data["containers"]["ok"]
    protocol_container = %{client_container | inspect: encoded_container["inspect"]}

    core =
      Core.new(
        protocol_container,
        tag_info(),
        image(),
        Settings.default(),
        true,
        false,
        DateTime.utc_now()
      )

    assert core.configuration.hostname == "app"
    assert core.state.status == "running"
    assert core.state.health == %{"Status" => "healthy", "FailingStreak" => 0}
  end

  test "normalizes a missing protocol stack name" do
    client_container = %{client_container(resources: nil) | stack_name: nil}

    core =
      Core.new(
        client_container,
        tag_info(),
        image(),
        Settings.default(),
        true,
        false,
        DateTime.utc_now()
      )

    assert core.stack_name == ""
  end

  defp client_container(opts) do
    id = Keyword.get(opts, :id, "container-id")
    inspect = inspect_response(id)

    %ClientLib.Container{
      name: "example",
      id: id,
      is_running: true,
      stack_name: "example",
      image_tag: "example/app:latest",
      image_id: "sha256:image-id",
      inspect: inspect,
      resources: Keyword.fetch!(opts, :resources)
    }
  end

  defp image do
    %Domain.Image{
      id: "sha256:image-id",
      digest: "sha256:digest",
      size: 1024,
      build_date: ~U[2024-04-26 16:44:57Z],
      registry_url: "https://hub.docker.com/r/example/app",
      metadata: Domain.Image.Metadata.default("example/app:latest")
    }
  end

  defp tag_info do
    Domain.TagInfo.new(
      "example/app:latest",
      "linux/amd64",
      "sha256:digest",
      DateTime.utc_now(),
      DateTime.utc_now()
    )
  end

  defp inspect_response(id \\ "container-id") do
    %Model.ContainerInspectResponse{
      Id: id,
      Created: "2024-04-26T16:44:57.875264024Z",
      Image: "sha256:image-id",
      Config: %Model.ContainerConfig{
        Env: ["APP_ENV=test"],
        Image: "example/app:latest",
        Hostname: "app",
        Cmd: ["start"],
        Labels: %{"com.docker.compose.project" => "example"}
      },
      NetworkSettings: %Model.NetworkSettings{Networks: %{}, Ports: %{}},
      HostConfig: %Model.HostConfig{Binds: [], RestartPolicy: %Model.RestartPolicy{Name: "unless-stopped"}},
      State: %Model.ContainerState{
        Status: "running",
        Running: true,
        Paused: false,
        Restarting: false,
        OOMKilled: false,
        Dead: false,
        Pid: 123,
        ExitCode: 0,
        Error: "",
        StartedAt: "2024-04-26T16:45:00Z",
        FinishedAt: "0001-01-01T00:00:00Z",
        Health: %Model.Health{
          Status: "healthy",
          FailingStreak: 0,
          Log: [
            %Model.HealthcheckResult{
              Start: ~U[2024-04-26 16:45:01Z],
              End: "2024-04-26T16:45:02Z",
              ExitCode: 0,
              Output: "ok"
            }
          ]
        }
      }
    }
    |> Exdock.Protocol.Value.encode()
  end

  defp stats_response(read_at) do
    %Model.ContainerStatsResponse{
      read: DateTime.to_iso8601(read_at),
      memory_stats: %Model.ContainerMemoryStats{usage: 87_281_664, limit: 4_294_967_296},
      cpu_stats: %Model.ContainerCpuStats{
        cpu_usage: %Model.ContainerCpuUsage{total_usage: 1_050},
        system_cpu_usage: 5_000,
        online_cpus: 4
      },
      precpu_stats: %Model.ContainerCpuStats{
        cpu_usage: %Model.ContainerCpuUsage{total_usage: 1_000},
        system_cpu_usage: 4_000
      },
      blkio_stats: %Model.ContainerBlkioStats{
        io_service_bytes_recursive: [
          %{"op" => "read", "value" => 100},
          %{"op" => "write", "value" => 75}
        ]
      },
      networks: %{"eth0" => %{"rx_bytes" => 1000, "tx_bytes" => 200}}
    }
    |> Exdock.Protocol.Value.encode()
  end
end
