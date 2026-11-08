defmodule Exdock.DockerTest.Driver do
  @moduledoc false
  alias Exdock.DockerTest.Harness, as: H
  alias Exdock.ClientLib.Jobs
  alias Jobs.Context

  def export_release!(context, directory) do
    File.mkdir_p!(directory)

    images =
      for {kind, tag} <- [{"server", "suite-server:local"}, {"agent", "suite-agent:local"}], into: %{} do
        [image] = H.docker!(context, ["image", "inspect", tag]) |> JSON.decode!()
        {kind, %{"local_tag" => tag, "id" => image["Id"], "labels" => image["Config"]["Labels"]}}
      end

    H.docker!(
      context,
      ["image", "save", "--output", Path.join(directory, "images.tar"), "suite-server:local", "suite-agent:local"],
      180
    )

    File.write!(Path.join(directory, "images.json"), JSON.encode!(images) <> "\n")
    File.cp!(Path.join(context.artifacts, "engine.txt"), Path.join(directory, "tested-engine.txt"))
    IO.puts("Exported passing production images to #{directory}")
  end

  defp verify_packaging!(context, image) do
    [inspect] = H.docker!(context, ["image", "inspect", image]) |> JSON.decode!()
    labels = inspect["Config"]["Labels"]

    for {key, expected} <- [
          {"org.opencontainers.image.licenses", "MIT"},
          {"org.opencontainers.image.version", System.get_env("EXDOCK_IMAGE_VERSION", "dev")},
          {"org.opencontainers.image.revision", System.get_env("EXDOCK_IMAGE_REVISION", "unknown")},
          {"org.opencontainers.image.source", System.get_env("EXDOCK_IMAGE_SOURCE", "")}
        ] do
      unless labels[key] == expected, do: raise("#{image}: wrong #{key}")
    end

    H.docker!(context, [
      "run",
      "--rm",
      "--user",
      "nonroot",
      "--entrypoint",
      "sh",
      image,
      "-c",
      "test -s /app/LICENSE && test -d /app/licenses/dependencies && test -n \"$(find /app/licenses/dependencies -type f | head -n 1)\""
    ])
  end

  def start_release!(context) do
    for {image, file} <- [{"suite-server:local", "Dockerfile"}, {"suite-agent:local", "lib/exdock_client/Dockerfile"}] do
      IO.puts("Building production release #{image}; output is recorded in commands.log")

      H.setup_command!(
        context,
        [
          "build",
          "--build-arg",
          "IMAGE_VERSION=#{System.get_env("EXDOCK_IMAGE_VERSION", "dev")}",
          "--build-arg",
          "IMAGE_REVISION=#{System.get_env("EXDOCK_IMAGE_REVISION", "unknown")}",
          "--build-arg",
          "IMAGE_SOURCE=#{System.get_env("EXDOCK_IMAGE_SOURCE", "")}",
          "-f",
          file,
          "-t",
          image,
          "."
        ],
        1800
      )

      verify_packaging!(context, image)
    end

    auth = Base.encode64(:crypto.strong_rand_bytes(32))
    secret = Base.encode64(:crypto.strong_rand_bytes(64))
    vault = Base.encode64(:crypto.strong_rand_bytes(32))

    H.docker!(context, [
      "run",
      "-d",
      "--name",
      "suite-server",
      "--network",
      "suite-net",
      "--label",
      "exdock.protected=true",
      "-e",
      "AUTH_KEY=#{auth}",
      "-e",
      "SECRET_KEY_BASE=#{secret}",
      "-e",
      "DB_VAULT_KEY=#{vault}",
      "-e",
      "UI_EMAIL=integration@example.com",
      "-e",
      "UI_PASSWORD=integration-test-password",
      "-e",
      "PHX_HOST=localhost",
      "-e",
      "ERL_FLAGS=+S 2:2",
      "suite-server:local"
    ])

    H.eventually!(
      fn ->
        case rpc(context, "true", 10) do
          {:ok, true} -> {:ok, true}
          _ -> false
        end
      end,
      "production server startup",
      90_000
    )

    H.docker!(context, [
      "run",
      "-d",
      "--name",
      "suite-agent",
      "--network",
      "suite-net",
      "--label",
      "exdock.protected=true",
      "-v",
      "/var/run/docker.sock:/var/run/docker.sock",
      "-e",
      "AUTH_KEY=#{auth}",
      "-e",
      "NODE_NAME=docker-test-node",
      "-e",
      "SERVER_HOST=suite-server",
      "-e",
      "SERVER_PORT=5000",
      "-e",
      "RELEASE_DISTRIBUTION=sname",
      "-e",
      "RELEASE_NODE=exdock_client_test",
      "-e",
      "ERL_FLAGS=+S 2:2",
      "suite-agent:local"
    ])

    H.eventually!(
      fn ->
        case rpc(context, "\"docker-test-node\" in Exdock.Runtime.Coordinator.query({:page, []}).nodes_list", 10) do
          {:ok, true} -> {:ok, true}
          _ -> false
        end
      end,
      "production agent authentication and readiness",
      90_000
    )

    context
  end

  def command(_context, :adapter, action, target) do
    execution = Context.runtime()
    id = "docker-test-" <> Base.encode16(:crypto.strong_rand_bytes(8))

    case action do
      :start -> Jobs.container_start(id, target, execution)
      :stop -> Jobs.container_stop(id, target, execution)
      :restart -> Jobs.container_restart(id, target, execution)
      :pull -> Jobs.image_pull(id, target, execution)
      :recreate -> Jobs.container_recreate(id, target, false, execution)
      :update -> Jobs.container_recreate(id, target, true, execution)
    end
    |> case do
      {:ok, _} -> :ok
      {:error, error, _} -> {:error, error}
    end
  end

  def command(context, :release, action, target) do
    # Resolve current Docker facts through the real refresh command before
    # constructing a state-aware command, just as the application does.
    :ok = submit!(context, "Exdock.Runtime.Command.Cluster.refresh_node(\"docker-test-node\", :hidden)")
    target = inspect(target)

    command =
      case action do
        :start -> "Exdock.Runtime.Command.Container.start(\"docker-test-node\", #{target})"
        :stop -> "Exdock.Runtime.Command.Container.stop(\"docker-test-node\", #{target})"
        :restart -> "Exdock.Runtime.Command.Container.restart(\"docker-test-node\", #{target})"
        :pull -> "Exdock.Runtime.Command.Image.pull([%{node: \"docker-test-node\", image_tag: #{target}}])"
        :recreate -> "Exdock.Runtime.Command.Container.recreate([{\"docker-test-node\", #{target}}], false)"
        :update -> "Exdock.Runtime.Command.Container.recreate([{\"docker-test-node\", #{target}}], true)"
      end

    submit!(context, command)
  end

  defp submit!(context, command) do
    commands = command |> List.wrap() |> Enum.join(",\n")

    code = """
    :ok = Exdock.Events.subscribe(:operations)
    ids = Enum.map([#{commands}], fn command ->
      operation_id = Ecto.UUID.generate()
      :ok = Exdock.Runtime.Coordinator.submit(operation_id, command, operation_kind: Exdock.Runtime.Command.kind(command))
      operation_id
    end)
    results = Enum.map(ids, fn operation_id ->
      receive do
        {:exdock_event, :operations, _, %{id: ^operation_id, state: :finished, result: result}} ->
          success = case result do
            %Exdock.Server.Jobs.Result{error: nil} -> true
            nil -> true
            %{status: :completed} -> true
            _ -> false
          end
          %{success: success, result: inspect(result)}
      after
        60_000 -> raise "operation did not reach a terminal result"
      end
    end)
    %{success: Enum.all?(results, & &1.success), result: results}
    """

    case rpc(context, code, 75) do
      {:ok, %{"success" => true}} -> :ok
      {:ok, result} -> {:error, result}
      {:error, reason} -> raise "Release RPC failed: #{inspect(reason)}"
    end
  end

  def recreate_then_stop(context, target) do
    :ok = submit!(context, "Exdock.Runtime.Command.Cluster.refresh_node(\"docker-test-node\", :hidden)")
    target = inspect(target)

    submit!(context, [
      "Exdock.Runtime.Command.Container.recreate([{\"docker-test-node\", #{target}}], false)",
      "Exdock.Runtime.Command.Container.stop(\"docker-test-node\", #{target})"
    ])
  end

  def recreate_across_disconnect(context, target) do
    task =
      Task.Supervisor.async_nolink(Exdock.Client.Connection.TaskSupervisor, fn ->
        command(context, :release, :recreate, target)
      end)

    H.eventually!(
      fn ->
        case agent_rpc(
               context,
               "Enum.any?(:sys.get_state(Exdock.ClientLib.CommandDispatcher).command_tasks, fn {_, t} -> t.kind == \"container_recreate\" end)",
               10
             ) do
          {:ok, true} -> {:ok, true}
          _ -> false
        end
      end,
      "active recreation before disconnect"
    )

    {:ok, _} = agent_rpc(context, ":ssl.close(:sys.get_state(Exdock.Client.Connection.TCPClient).socket); true", 10)
    result = Task.await(task, 30_000)

    H.eventually!(
      fn ->
        {logs, _} = H.docker(context, ["logs", "suite-agent"], 10)
        if String.contains?(logs, "runtime_busy"), do: {:ok, true}, else: false
      end,
      "runtime replacement deferred while recreation is active",
      35_000
    )

    H.eventually!(
      fn ->
        case rpc(context, "\"docker-test-node\" in Exdock.Runtime.Coordinator.query({:page, []}).nodes_list", 10) do
          {:ok, true} -> {:ok, true}
          _ -> false
        end
      end,
      "agent reconnection after active work drains",
      90_000
    )

    result
  end

  def await_container_snapshot!(context, target, id) do
    expression = """
    case Exdock.Runtime.Coordinator.query({:node_page, "docker-test-node", []}).node do
      %Exdock.ReadModel.Node{containers_core: containers} ->
        Enum.any?(containers, fn {key, core} -> key.name == #{inspect(target)} and key.id == #{inspect(id)} and core.is_running end)
      _ -> false
    end
    """

    H.eventually!(
      fn ->
        case rpc(context, expression, 10) do
          {:ok, true} -> {:ok, true}
          _ -> false
        end
      end,
      "automatic post-reconnect container snapshot"
    )
  end

  def rpc(context, code, timeout), do: release_rpc(context, "suite-server", "exdock", "Jason", code, timeout)
  def agent_rpc(context, code, timeout), do: release_rpc(context, "suite-agent", "exdock_client", "JSON", code, timeout)

  defp release_rpc(context, container, release, encoder, code, timeout) do
    expression = "value = (#{code}); IO.puts(\"EXDOCK_TEST_RESULT:\" <> #{encoder}.encode!(value))"

    case H.docker(context, ["exec", container, "/app/bin/#{release}", "rpc", expression], timeout) do
      {output, 0} ->
        case Regex.run(~r/^EXDOCK_TEST_RESULT:(.+)$/m, output) do
          [_, json] -> {:ok, JSON.decode!(json)}
          _ -> {:error, output}
        end

      {output, _} ->
        {:error, output}
    end
  end
end
