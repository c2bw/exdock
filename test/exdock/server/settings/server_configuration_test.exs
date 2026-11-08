defmodule Exdock.ConfigurationTest do
  use Exdock.DataCase, async: false

  alias Exdock.Configuration
  alias Exdock.Server.State
  alias Exdock.Server.State.ConfigurationProjection
  alias Exdock.Server.State.Storage
  alias Exdock.Server.State.Storage.Cluster
  alias Exdock.Domain

  alias Exdock.Domain.Container.Settings, as: ContainerSettings
  alias Exdock.Domain.Image.Settings, as: ImageSettings
  alias Exdock.Domain.Node.Settings, as: NodeSettings
  alias Exdock.Domain.UserSettings

  test "from_state assembles the export payload from runtime storage" do
    user_settings =
      UserSettings.default()
      |> Map.put(:auto_update_above, 4)

    state = %State{
      settings: %Storage.Settings{user: %{UserSettings.default_user() => user_settings}},
      cluster: %Cluster{storage: state_storage()}
    }

    configuration = ConfigurationProjection.from_state(state)

    assert configuration.user_settings == Map.from_struct(user_settings)

    assert %{
             "edge_node" => %{web_ui: "https://edge.local"},
             "worker_node" => %{web_ui: "https://worker.local"}
           } =
             configuration.nodes_settings

    assert %{
             "edge_node" => %{
               "image-edge/app:1.0" => %{delete_lock: true},
               "image-edge/app:2.0" => %{delete_lock: false}
             },
             "worker_node" => %{}
           } = configuration.images_settings

    assert %{
             "edge_node" => %{"api" => %{priority: 5}, "worker" => %{priority: 2}},
             "worker_node" => %{}
           } = configuration.containers_settings

    assert %{
             "edge/app:1.0" => %{repository_url: "https://edge.local/metadata"},
             "edge/app:2.0" => %{repository_url: "https://edge.local/metadata/2"}
           } =
             configuration.repository_overrides

    refute Map.has_key?(configuration.repository_overrides, "default/app:latest")
  end

  test "get_node_settings uses canonical string node keys and defaults missing entries" do
    settings = %NodeSettings{web_ui: "https://edge.local"}
    configuration = %Configuration{nodes_settings: %{"edge_node" => settings}}

    assert Configuration.node_settings(configuration, "edge_node") == settings
    assert Configuration.node_settings(configuration, "unknown_node") == %{web_ui: ""}
  end

  test "from_json applies defaults for missing top-level export sections" do
    assert {:ok, configuration} =
             Configuration.from_json(Jason.encode!(%{"nodes_settings" => %{"edge_node" => %{"web_ui" => "https://edge.local"}}}))

    assert configuration.user_settings == nil
    assert configuration.nodes_settings == %{"edge_node" => %{"web_ui" => "https://edge.local"}}
    assert configuration.images_settings == %{}
    assert configuration.containers_settings == %{}
    assert configuration.repository_overrides == %{}
  end

  test "from_json rejects non-object top-level JSON" do
    assert {:error, "expected an object"} = Configuration.from_json("[1, 2, 3]")
  end

  test "to_json serializes the configuration boundary shape" do
    metadata = %Domain.Image.Metadata{repository_url: "https://edge.local/metadata"}

    configuration = %Configuration{
      user_settings: UserSettings.default(),
      nodes_settings: %{"edge_node" => %NodeSettings{web_ui: "https://edge.local"}},
      images_settings: %{"edge_node" => %{"edge/app:1.0" => %ImageSettings{delete_lock: true}}},
      containers_settings: %{"edge_node" => %{"api" => %ContainerSettings{}}},
      repository_overrides: %{"edge/app:1.0" => metadata}
    }

    assert {:ok, decoded} = configuration |> Configuration.to_json() |> Jason.decode()
    assert decoded["nodes_settings"]["edge_node"] == %{"web_ui" => "https://edge.local"}
    assert decoded["images_settings"]["edge_node"]["edge/app:1.0"]["delete_lock"] == true
    assert decoded["repository_overrides"]["edge/app:1.0"] == %{"repository_url" => metadata.repository_url}
  end

  test "import_sections normalizes runtime structs without a JSON round trip" do
    configuration = %Configuration{
      user_settings: %UserSettings{automation_enabled: true},
      nodes_settings: %{"edge_node" => %NodeSettings{web_ui: "https://edge.local"}}
    }

    assert %{
             user_settings: %{"automation_enabled" => true},
             nodes_settings: %{"edge_node" => %{"web_ui" => "https://edge.local"}}
           } = Configuration.import_sections(configuration)
  end

  defp state_storage do
    Cluster.new().storage
    |> Storage.Nodes.set("edge_node", edge_node())
    |> Storage.Images.set_node("edge_node", [
      image("edge_node", "edge/app:1.0", "https://edge.local/metadata", true),
      image("edge_node", "edge/app:2.0", "https://edge.local/metadata/2", false),
      image(
        "edge_node",
        "default/app:latest",
        Domain.Image.Metadata.default("default/app:latest").repository_url,
        false
      )
    ])
    |> Storage.Containers.set_node("edge_node", [
      container("api", 5),
      container("worker", 2)
    ])
    |> Storage.Nodes.set("worker_node", worker_node())
    |> Storage.Images.set_node("worker_node", [])
    |> Storage.Containers.set_node("worker_node", [])
  end

  defp edge_node do
    %Domain.Node{
      node: "edge_node",
      settings: %NodeSettings{web_ui: "https://edge.local"}
    }
  end

  defp worker_node do
    %Domain.Node{
      node: "worker_node",
      settings: %NodeSettings{web_ui: "https://worker.local"}
    }
  end

  defp image(node, name, repository_url, delete_lock) when is_boolean(delete_lock) do
    %Domain.Image{
      node: node,
      id: "image-#{name}",
      name: name,
      metadata: %Domain.Image.Metadata{repository_url: repository_url},
      settings: %ImageSettings{delete_lock: delete_lock}
    }
  end

  defp container(name, priority) do
    %Domain.Container{
      node: "edge_node",
      name: name,
      core: %Domain.Container.Core{settings: %ContainerSettings{priority: priority}}
    }
  end
end
