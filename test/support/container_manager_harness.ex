defmodule ExdockWeb.ContainersLiveTest.ContainerManagerHarness do
  @moduledoc false

  use ExdockWeb, :live_view

  alias Exdock.ReadModel.Container, as: ContainerProjection
  alias Exdock.ReadModel.{Release, Repository, RepositoryPage}
  alias Exdock.Domain
  alias Exdock.Domain.Container.Core
  alias Exdock.Domain.Container.Core.ImageData
  alias Exdock.Domain.Container.Core.State
  alias Exdock.Domain.Container.Configuration
  alias Exdock.Domain.Container.Extended
  alias Exdock.Domain.Container.Settings

  @impl true
  def mount(_params, _session, socket) do
    core = core_fixture()
    {:ok, Phoenix.Component.assign(socket, core: core, clock_now: core.fetched_at, last_event: "")}
  end

  @impl true
  def handle_event(event, params, socket) do
    event_value =
      case {event, params} do
        {"container-recreate", %{"node" => node, "container_name" => name}} ->
          "#{node},#{name}"

        {"image-pull", %{"node" => node, "image_tag" => image_tag}} ->
          "#{node},#{image_tag}"

        _other ->
          params["container_name"] ||
            params["new_url"] ||
            params["nodename"] ||
            "submit"
      end

    {:noreply,
     Phoenix.Component.assign(
       socket,
       :last_event,
       "#{event}:#{event_value}"
     )}
  end

  @impl true
  def handle_info(:refresh_container_manager, socket) do
    send_update(ExdockWeb.Commons.ContainerManager, id: "container-manager")
    {:noreply, socket}
  end

  def handle_info(:advance_clock, socket) do
    {:noreply, Phoenix.Component.assign(socket, :clock_now, DateTime.add(socket.assigns.clock_now, 3600))}
  end

  def handle_info(:show_outdated_digest, socket) do
    core = socket.assigns.core
    image_data = %{core.image_data | status: :outdated}

    {:noreply, Phoenix.Component.assign(socket, :core, %{core | image_data: image_data})}
  end

  def handle_info(:stop_container, socket) do
    core = socket.assigns.core

    state = %{
      core.state
      | status: "exited",
        running: false,
        started_at: nil,
        finished_at: core.fetched_at
    }

    {:noreply, Phoenix.Component.assign(socket, :core, %{core | is_running: false, state: state})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="container-manager-harness">
      <.live_component
        module={ExdockWeb.Commons.ContainerManager}
        id="container-manager"
        modal_id="container-manager-modal"
        component_id="container-manager-component"
        render?={true}
        nodename="harness_node"
        container_name="api"
        core={@core}
        extended={Extended.new()}
        release_data={release_data_fixture()}
        clock_now={@clock_now}
      />
      <p id="last-container-manager-event">{@last_event}</p>
    </div>
    """
  end

  defp core_fixture do
    now = ~U[2026-06-01 10:00:00Z]

    %Core{
      is_running: true,
      stack_name: "api",
      configuration: %Configuration{
        created: DateTime.to_iso8601(now),
        restartpolicy: %{},
        image_name_with_id: "repo/api:latest@sha256:api",
        env: [],
        cmd: "",
        entrypoint: "",
        ports: [],
        binds: [],
        hostname: "api",
        networks: %{}
      },
      state: %State{
        status: "running",
        running: true,
        paused: false,
        restarting: false,
        oom_killed: false,
        dead: false,
        pid: 1_234,
        exit_code: 0,
        error: "",
        started_at: now,
        finished_at: nil,
        health: nil
      },
      json_compressed_inspect: :zlib.gzip("{}"),
      image_data: %ImageData{
        status: :updated,
        present_on_node: true,
        tag_info: %Domain.TagInfo{
          tag: "repo/api:latest",
          latest_digest: "sha256:remote-api-digest",
          latest_date: now
        },
        image: %Domain.Image{
          digest: "sha256:local-api-digest",
          build_date: now,
          registry_url: "https://example.com/api",
          size: 64_000,
          size_human: "64 kB",
          metadata: %Domain.Image.Metadata{repository_url: "https://github.com/example/api"}
        }
      },
      settings: %Settings{priority: 3, auto_update: :passthrough, labels: []},
      is_deleted: false,
      fetched_at: now
    }
    |> then(fn core ->
      ContainerProjection.from_domain(%{
        node: "harness_node",
        name: "api",
        id: "api-id",
        core: core,
        extended: nil
      }).core
    end)
  end

  defp release_data_fixture do
    repository_url = "https://github.com/example/api"

    %Repository{
      url: repository_url,
      page: %RepositoryPage{state: :ok, last_check: ~U[2026-06-01 10:00:00Z]},
      label: "github.com/example/api",
      releases: [
        release_fixture(repository_url, "v2.0.0", ~U[2026-06-01 10:00:00Z]),
        release_fixture(repository_url, "v1.0.0", ~U[2026-01-01 10:00:00Z])
      ]
    }
  end

  defp release_fixture(repository_url, version, released_at) do
    %Release{
      source: :github,
      repository: repository_url,
      name: "example/api",
      version: version,
      release_url: "#{repository_url}/releases/tag/#{version}",
      html_description: "<p>Release #{version}</p>",
      time_released: released_at,
      provider_icon: "github-mark.svg",
      repository_label: "github.com/example/api"
    }
  end
end
