defmodule Exdock.Domain.Container.ConfigurationTest do
  use ExUnit.Case, async: true

  alias DockerEngineAPI.Model
  alias Exdock.Protocol.Value
  alias Exdock.Domain.Container.Configuration

  test "new/1 normalizes nil docker collections into empty lists and maps" do
    configuration =
      %Model.ContainerInspectResponse{
        Created: "2026-06-30T15:43:22Z",
        Image: "sha256:image-id",
        Config: %Model.ContainerConfig{Image: "example/app:latest", Env: nil},
        HostConfig: %Model.HostConfig{Binds: nil, RestartPolicy: %Model.RestartPolicy{Name: "unless-stopped"}},
        NetworkSettings: %Model.NetworkSettings{Ports: nil, Networks: nil}
      }
      |> Value.encode()
      |> Configuration.new()

    assert %Configuration{
             env: [],
             binds: [],
             ports: %{},
             networks: %{},
             restartpolicy: %{"Name" => "unless-stopped"},
             image_name_with_id: "example/app:latest@sha256:image-id"
           } = configuration

    assert {:ok, _json} = Jason.encode(configuration)
  end

  test "port_binds_count counts only container ports with host bindings" do
    configuration = %Configuration{
      ports: %{
        "80/tcp" => [%{host_ip: "0.0.0.0", host_port: "8080"}],
        "443/tcp" => nil,
        "9000/tcp" => []
      }
    }

    assert Configuration.port_binds_count(configuration) == 2
  end

  test "has_network_host_bind checks the docker host network" do
    assert Configuration.has_network_host_bind(%Configuration{networks: %{"host" => %{}}})
    refute Configuration.has_network_host_bind(%Configuration{networks: %{"bridge" => %{}}})
  end
end
