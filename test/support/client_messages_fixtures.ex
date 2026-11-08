defmodule Exdock.Server.State.ClientMessagesFixtures do
  @moduledoc false

  alias DockerEngineAPI.Model
  alias Exdock.Protocol.Messages
  alias Exdock.Protocol.Snapshot, as: Client
  alias Exdock.Server.Jobs.{Job, Result}
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Containers
  alias Exdock.Domain.Container

  def sqlite_total_changes do
    %{rows: [[count]]} = Ecto.Adapters.SQL.query!(Exdock.Repo, "SELECT total_changes()", [])
    count
  end

  def base_state do
    node =
      "node"
      |> Exdock.Domain.Node.default()
      |> Exdock.Domain.Node.put_metadata(%{"platform" => "linux/amd64"})

    storage = Storage.Nodes.set(Storage.Cluster.new().storage, "node", node)

    %State{
      cluster: %Storage.Cluster{storage: storage},
      tags: %Storage.TagsInfo{tags: %{}},
      repositories: %Storage.Repositories{repositories: %{}}
    }
  end

  def state_with_container(container_id \\ "container-id") do
    state = base_state()
    image = storage_image()

    storage =
      state.cluster.storage
      |> Storage.Images.set_node("node", [image])
      |> Containers.set_node("node", [storage_container(image, container_id)])

    %{state | cluster: %Storage.Cluster{storage: storage}}
  end

  def image_result_set, do: %{ok: [client_image()], errored: []}
  def container_result_set, do: %{ok: [container_result()], errored: []}

  def node_refresh_message(container) do
    %Messages.JobResult{
      job: %Job{id: "refresh-id", name: :node_refresh},
      result: %Result{
        node: "node",
        data: {%{ok: [container], errored: []}, image_result_set()},
        error: nil
      }
    }
  end

  def empty_node_refresh_message do
    %Messages.JobResult{
      job: %Job{id: "refresh-id", name: :node_refresh},
      result: %Result{
        node: "node",
        data: {%{ok: [], errored: []}, %{ok: [], errored: []}},
        error: nil
      }
    }
  end

  def container_result(id \\ "container-id", health_log_start \\ ~U[2026-07-21 10:40:00Z]) do
    %Client.Container{
      name: "app",
      id: id,
      is_running: true,
      stack_name: "app",
      image_tag: "example/app:latest",
      image_id: "sha256:image-id",
      inspect: container_inspect(health_log_start)
    }
  end

  def client_image do
    %Client.Image{
      id: "sha256:image-id",
      name: "example/app",
      tags: ["example/app:latest"],
      digest: "sha256:image-digest",
      size: 1_024,
      shared_size: 128,
      build_date: ~U[2026-06-30 15:43:22Z]
    }
  end

  def stats_response do
    %Model.ContainerStatsResponse{
      read: DateTime.utc_now() |> DateTime.to_iso8601(),
      memory_stats: %Model.ContainerMemoryStats{usage: 1024, limit: 2048},
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
          %{"op" => "read", "value" => 10},
          %{"op" => "write", "value" => 7}
        ]
      },
      networks: %{"eth0" => %{"rx_bytes" => 12, "tx_bytes" => 15}}
    }
    |> Exdock.Protocol.Value.encode()
  end

  defp storage_image do
    Exdock.Domain.Image.from_client(client_image(), "node", nil, true)
  end

  defp storage_container(image, container_id) do
    Container.from_client(
      "node",
      container_result(container_id),
      nil,
      image,
      Exdock.Domain.TagInfo.default("example/app:latest", "linux/amd64"),
      false,
      DateTime.utc_now()
    )
  end

  defp container_inspect(health_log_start) do
    %Model.ContainerInspectResponse{
      Id: "container-id",
      Created: "2026-06-30T15:43:57Z",
      Image: "sha256:image-id",
      Config: %Model.ContainerConfig{
        Env: ["APP_ENV=test"],
        Image: "example/app:latest",
        Hostname: "app",
        Cmd: ["start"],
        Labels: %{"com.docker.compose.project" => "app"}
      },
      NetworkSettings: %Model.NetworkSettings{Networks: %{}, Ports: %{}},
      HostConfig: %Model.HostConfig{
        Binds: [],
        RestartPolicy: %Model.RestartPolicy{Name: "unless-stopped"}
      },
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
        StartedAt: "2026-06-30T15:44:00Z",
        FinishedAt: "0001-01-01T00:00:00Z",
        Health: %Model.Health{
          Status: "healthy",
          FailingStreak: 0,
          Log: [
            %Model.HealthcheckResult{
              Start: health_log_start,
              End: DateTime.add(health_log_start, 1, :second) |> DateTime.to_iso8601(),
              ExitCode: 0,
              Output: "ok"
            }
          ]
        }
      }
    }
    |> Exdock.Protocol.Value.encode()
  end
end
