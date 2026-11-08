defmodule Exdock.OperationsTest do
  use ExUnit.Case, async: false

  alias Exdock.Operations
  alias Exdock.Events
  alias Exdock.Runtime.{Command, Mutation, MutationContract}
  alias Exdock.Configuration
  alias Exdock.Server.State.Storage
  alias Exdock.OperationsTest.CastSink

  setup do
    start_sink!(:operations_server_sink, Exdock.Runtime.Coordinator)
    start_sink!(:operations_logging_sink, Exdock.Server.Logging)
    :ok = Events.subscribe(:operations)
    :ok
  end

  test "container commands dispatch canonical job builders" do
    assert_operation(Operations.start_container("node_a", "web"))
    assert_command(Command.Container.start("node_a", "web"))

    assert_operation(Operations.stop_container("node_a", "web"))
    assert_command(Command.Container.stop("node_a", "web"))

    assert_operation(Operations.restart_container("node_a", "web"))
    assert_command(Command.Container.restart("node_a", "web"))

    assert_operation(Operations.fetch_container_logs("node_a", "web"))
    assert_command(Command.Container.logs("node_a", "web"))
  end

  test "cluster, image, registry, and release commands dispatch typed jobs" do
    pulls = [%{node: "node_a", image_tag: "example/web:latest"}]
    containers = [{"node_a", "web"}]

    assert_operation(Operations.refresh_cluster())
    assert_command(Command.Cluster.refresh_cluster())

    assert_operation(Operations.refresh_node("node_a", :hidden))
    assert_command(Command.Cluster.refresh_node("node_a", :hidden))

    assert_operation(Operations.fetch_registry_cluster())
    assert_command(Command.Cluster.fetch_registry_cluster())

    assert_operation(Operations.fetch_registry_node("node_a"))
    assert_command(Command.Cluster.fetch_registry_node("node_a"))

    assert_operation(Operations.pull_images(pulls))
    assert_command(Command.Image.pull(pulls))

    assert_operation(Operations.delete_image("node_a", "sha256:image"))
    assert_command(Command.Image.delete("node_a", "sha256:image"))

    assert_operation(Operations.delete_unused_images("node_a"))
    assert_command(Command.Image.delete_unused("node_a"))

    assert_operation(Operations.recreate_containers(containers, true))
    assert_command(Command.Container.recreate(containers, true))

    assert_operation(Operations.fetch_repositories(["https://github.com/example/web"]))
    assert_command(Command.Repository.fetch(["https://github.com/example/web"]))

    assert_operation(Operations.fetch_releases([:ok]))
    assert_command(Command.Repository.fetch_releases([:ok]))
  end

  test "settings commands dispatch explicit state-change payloads" do
    assert_operation(Operations.set_container_priority("node_a", "web", 20))
    assert_state_change(Storage.Containers, :priority, {"node_a", "web", 20})

    priorities = [{"node_a", "web", 10}, {"node_b", "worker", 20}]
    assert_operation(Operations.set_container_priorities(priorities))
    assert_state_change(Storage.Containers, :priority, [{"node_a", "web", 10}, {"node_b", "worker", 20}])

    assert_operation(Operations.set_container_auto_update("node_a", "web", :enabled))
    assert_state_change(Storage.Containers, :auto_update, {"node_a", "web", :enabled})

    assert_operation(Operations.set_image_repository_url("example/web:latest", "https://github.com/example/web"))
    assert_state_change(Storage.Images, :repository_url, {:single, "example/web:latest", "https://github.com/example/web"})

    overrides = [{"example/worker:latest", "https://github.com/example/worker"}]
    assert_operation(Operations.set_image_repository_urls(overrides))
    assert_state_change(Storage.Images, :repository_url, {:list, overrides})

    assert_operation(Operations.set_image_delete_lock("node_a", "sha256:image", true))
    assert_state_change(Storage.Images, :delete_lock, {"node_a", "sha256:image", true})

    assert_operation(Operations.change_user_setting(:container_resources, true))
    assert_state_change(Storage.Settings, :user_setting, {:container_resources, true})

    assert_operation(Operations.change_node_setting("node_a", :web_ui, "https://node-a.example"))
    assert_state_change(Storage.Nodes, :setting, {"node_a", :web_ui, "https://node-a.example"})

    assert_operation(Operations.set_cron_string("0 4 * * *"))
    assert_state_change(Storage.Settings, :user_setting, {:cron_string, "0 4 * * *"})

    configuration = %Configuration{repository_overrides: %{"example/web:latest" => "https://github.com/example/web"}}
    assert_operation(Operations.import_server_configuration(configuration))
    assert_state_change(Storage.Settings, :import, configuration)
  end

  test "setting commands reject unknown keys and invalid values before dispatch" do
    assert Operations.change_user_setting(:unknown, true) ==
             {:error, {:unknown_user_setting, :unknown}}

    assert Operations.change_user_setting(:container_resources, :sometimes) ==
             {:error, {:invalid_user_setting_value, :container_resources}}

    assert Operations.change_user_setting(:cron_string, "not a cron") ==
             {:error, {:invalid_user_setting_value, :cron_string}}

    assert Operations.change_node_setting("node_a", :unknown, "value") ==
             {:error, {:unknown_node_setting, :unknown}}

    assert Operations.change_node_setting("node_a", :web_ui, 123) ==
             {:error, {:invalid_node_setting_value, :web_ui}}

    refute_receive {:operation_call, Exdock.Runtime.Coordinator, {:submit_command, _operation_id, _command, _opts}}
  end

  test "commands reject invalid node identifiers without raising or dispatching" do
    invalid_commands = [
      fn -> Operations.refresh_node(:node) end,
      fn -> Operations.fetch_registry_node("has spaces") end,
      fn -> Operations.start_container(:node, "web") end,
      fn -> Operations.recreate_containers([{"has spaces", "web"}], false) end,
      fn -> Operations.pull_images([%{node: :node, image_tag: "repo/web:latest"}]) end,
      fn -> Operations.delete_image("has spaces", "sha256:image") end,
      fn -> Operations.set_container_priority(:node, "web", 3) end,
      fn -> Operations.change_node_setting("has spaces", :web_ui, "https://node.example") end
    ]

    assert Enum.map(invalid_commands, & &1.()) == [
             {:error, {:invalid_node, :invalid_type}},
             {:error, {:invalid_node, :invalid_format}},
             {:error, {:invalid_node, :invalid_type}},
             {:error, {:invalid_node, :invalid_format}},
             {:error, {:invalid_node, :invalid_type}},
             {:error, {:invalid_node, :invalid_format}},
             {:error, {:invalid_node, :invalid_type}},
             {:error, {:invalid_node, :invalid_format}}
           ]

    refute_receive {:operation_call, Exdock.Runtime.Coordinator, {:submit_command, _operation_id, _command, _opts}}
  end

  test "automation and logging commands hide process APIs" do
    automation_id = assert_operation(Operations.run_automation())
    assert_receive {:operation_call, Exdock.Runtime.Coordinator, {:submit_periodic_job, ^automation_id}}

    clear_errors_id = assert_operation(Operations.clear_errors())
    assert_receive {:operation_call, Exdock.Server.Logging, {:submit_clear_errors, ^clear_errors_id}}
  end

  defp start_sink!(id, name) do
    if Process.whereis(name) do
      raise "unexpected process registered as #{inspect(name)}"
    end

    start_supervised!(%{
      id: id,
      start: {CastSink, :start_link, [{self(), name}]}
    })
  end

  defp assert_command(command) do
    assert_receive {:operation_call, Exdock.Runtime.Coordinator, {:submit_command, operation_id, ^command, opts}}
    assert Ecto.UUID.cast(operation_id) == {:ok, operation_id}
    assert Keyword.fetch!(opts, :operation_kind) == operation_kind(command)
  end

  defp assert_state_change(module, identifier, data) do
    domain = mutation_domain(module)
    assert {:ok, expected_data} = MutationContract.normalize_payload(domain, identifier, data)

    assert_receive {:operation_call, Exdock.Runtime.Coordinator,
                    {:submit_command, operation_id,
                     %{
                       mutation: %Mutation{
                         domain: ^domain,
                         action: ^identifier,
                         data: ^expected_data
                       }
                     }, opts}}

    assert Ecto.UUID.cast(operation_id) == {:ok, operation_id}
    assert is_atom(Keyword.fetch!(opts, :operation_kind))
  end

  defp mutation_domain(Storage.Settings), do: :settings
  defp mutation_domain(Storage.Nodes), do: :nodes
  defp mutation_domain(Storage.Images), do: :images
  defp mutation_domain(Storage.Containers), do: :containers

  defp assert_operation({:ok, operation_id}) do
    assert Ecto.UUID.cast(operation_id) == {:ok, operation_id}

    assert_receive {:exdock_event, :operations, _revision, %{id: ^operation_id, state: :accepted}}

    operation_id
  end

  defp operation_kind(command), do: Command.kind(command)
end
