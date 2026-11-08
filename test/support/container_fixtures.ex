defmodule ExdockWeb.TestFixtures.Container do
  @moduledoc false

  alias Exdock.ReadModel.Container
  alias Exdock.ReadModel.Container.Core

  @spec read_model(keyword() | map()) :: Container.t()
  def read_model(attrs \\ []) do
    attrs = Map.new(attrs)
    name = attrs |> Map.get(:name, "api") |> to_string()
    node = attrs |> Map.get(:node, "node_a") |> to_string()
    running? = Map.get(attrs, :is_running, true) == true
    now = Map.get(attrs, :now, ~U[2026-06-01 10:00:00Z])

    %Container{
      node: node,
      name: name,
      id: attrs |> Map.get(:id, "#{name}-id") |> to_string(),
      core: %Core{
        is_running: running?,
        stack_name: Map.get(attrs, :stack_name, "api"),
        configuration: Map.get(attrs, :configuration, %{networks: %{}, ports: %{}}),
        state: %{
          status: if(running?, do: "running", else: "exited"),
          running: running?,
          paused: false,
          restarting: false,
          oom_killed: false,
          dead: false,
          pid: Map.get(attrs, :pid, 1_234),
          exit_code: 0,
          error: "",
          started_at: if(running?, do: now, else: nil),
          finished_at: if(running?, do: nil, else: now),
          health: nil
        },
        image_status: Map.get(attrs, :image_status, :updated),
        image_tag: Map.get(attrs, :image_tag, "repo/#{name}:latest"),
        image_url: Map.get(attrs, :image_url, "https://example.com/#{name}"),
        image_size: Map.get(attrs, :image_size, 64_000),
        image_size_human: Map.get(attrs, :image_size_human, "64 kB"),
        image_present_on_node: Map.get(attrs, :image_present_on_node, false),
        image_build_date: Map.get(attrs, :image_build_date, now),
        remote_image_date: Map.get(attrs, :remote_image_date, now),
        repository_url: Map.get(attrs, :repository_url, "https://github.com/example/#{name}"),
        json_compressed_inspect: :zlib.gzip("{}"),
        image_data: %{},
        settings: %{
          priority: Map.get(attrs, :priority, 3),
          auto_update: Map.get(attrs, :auto_update, :passthrough),
          labels: Map.get(attrs, :labels, [])
        },
        is_deleted: Map.get(attrs, :is_deleted, false),
        fetched_at: Map.get(attrs, :fetched_at, now)
      },
      extended: Container.empty_extended()
    }
  end
end
