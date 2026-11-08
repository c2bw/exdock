defmodule ExdockWeb.ContainersLiveFixtures do
  @moduledoc false

  require ExUnit.Assertions

  alias Exdock.Database
  alias Exdock.Server.State.Storage.Persistence.Node, as: NodePersistence
  alias Exdock.Server.State.Storage.Persistence.TagInfo, as: TagInfoPersistence
  alias Exdock.Domain
  alias Exdock.Domain.Container.Configuration
  alias Exdock.Domain.Container.Core.State

  def seed_node_with_containers(opts \\ []) do
    node = "containers-node-#{System.unique_integer([:positive])}"
    now = ~U[2026-06-01 10:00:00Z]
    running? = Keyword.get(opts, :running?, false)

    :ok =
      node
      |> Domain.Node.default()
      |> Domain.Node.set_fetched_at(DateTime.utc_now())
      |> NodePersistence.insert()

    updated_image =
      image_record(
        node,
        "updated",
        "sha256:updated-digest",
        64_000,
        12_345,
        now
      )

    outdated_image =
      image_record(
        node,
        "outdated",
        "sha256:outdated-local-digest",
        65_000,
        12_346,
        now
      )

    {:ok, _} = Database.Image.insert(updated_image)
    {:ok, _} = Database.Image.insert(outdated_image)

    insert_tag_info(
      "repo/updated_image:latest",
      "sha256:updated-digest",
      now
    )

    insert_tag_info(
      "repo/outdated_image:latest",
      "sha256:outdated-remote-digest",
      now
    )

    updated_container =
      database_container(
        node: node,
        name: "web-updated",
        id: "container-updated-#{System.unique_integer([:positive])}",
        stack_name: "web",
        image_tag: "repo/updated_image:latest",
        image_id: updated_image.id,
        image_status: :updated,
        pid: 1_234,
        running?: running?,
        now: now
      )

    outdated_container =
      database_container(
        node: node,
        name: "worker-outdated",
        id: "container-outdated-#{System.unique_integer([:positive])}",
        stack_name: "worker",
        image_tag: "repo/outdated_image:latest",
        image_id: outdated_image.id,
        image_status: :outdated,
        pid: 1_235,
        running?: running?,
        now: now
      )

    {:ok, _} = Database.Container.insert(updated_container)
    {:ok, _} = Database.Container.insert(outdated_container)

    :ok =
      Exdock.Runtime.Coordinator.node_is_up(node, %{
        "platform" => "linux/amd64",
        "agent_version" => "1.1.0",
        "elixir_version" => "1.18.4",
        "otp_release" => "27"
      })

    expected_names = MapSet.new([updated_container.name, outdated_container.name])

    actual_names =
      Exdock.ReadModel.page([:containers]).containers
      |> Map.fetch!(to_string(node))
      |> MapSet.new(& &1.name)

    ExUnit.Assertions.assert(MapSet.subset?(expected_names, actual_names))

    %{
      node: node,
      updated_container: updated_container,
      outdated_container: outdated_container
    }
  end

  def mark_latest_image_present(container) do
    core = container.core
    image_data = %{core.image_data | present_on_node: true}
    %{container | core: %{core | image_data: image_data}}
  end

  defp image_record(node, kind, digest, size, shared_size, build_date) do
    %Database.Image.Record{
      node: node,
      id: "sha256:#{kind}-#{System.unique_integer([:positive])}",
      name: "repo/#{kind}_image",
      tags: ["repo/#{kind}_image:latest"],
      digest: digest,
      size: size,
      shared_size: shared_size,
      build_date: build_date
    }
  end

  defp insert_tag_info(tag, digest, date) do
    {:ok, _} =
      TagInfoPersistence.insert(Domain.TagInfo.new(tag, "linux/amd64", digest, date, date))
  end

  defp database_container(attrs) do
    attrs = Map.new(attrs)
    now = Map.fetch!(attrs, :now)
    image_id = Map.fetch!(attrs, :image_id)
    running? = Map.get(attrs, :running?, false)

    %{
      node: Map.fetch!(attrs, :node),
      name: Map.fetch!(attrs, :name),
      id: Map.fetch!(attrs, :id),
      is_deleted: false,
      stack_name: Map.fetch!(attrs, :stack_name),
      configuration: %Configuration{
        created: DateTime.to_iso8601(now),
        restartpolicy: %{},
        image_name_with_id: Map.fetch!(attrs, :image_tag) <> "@" <> image_id,
        env: [],
        cmd: [],
        entrypoint: [],
        ports: %{},
        binds: [],
        networks: %{}
      },
      state: %State{
        status: if(running?, do: "running", else: "exited"),
        running: running?,
        paused: false,
        restarting: false,
        oom_killed: false,
        dead: false,
        pid: Map.fetch!(attrs, :pid),
        exit_code: 0,
        error: "",
        started_at: if(running?, do: now, else: nil),
        finished_at: if(running?, do: nil, else: DateTime.to_iso8601(now)),
        health: nil
      },
      is_running: running?,
      image_status: Map.fetch!(attrs, :image_status),
      image_tag: Map.fetch!(attrs, :image_tag),
      image_id: image_id
    }
    |> Database.Container.new()
  end
end
