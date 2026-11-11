defmodule Exdock.Protocol.ContractTest do
  use ExUnit.Case, async: true

  alias Exdock.Protocol.{Command, Compatibility, Contract, Message}
  alias Exdock.Protocol.RuntimeBundle
  alias Exdock.Protocol.Snapshot

  test "keeps coordinated compatibility values in one contract" do
    assert Compatibility.wire_version() == Contract.current_version()
    assert Compatibility.agent_version() == "1.3.0"
    assert Compatibility.agent_requirement() == "~> 1.3.0"
    assert Compatibility.runtime_bundle_version() == "1"
  end

  test "uses the NodeWire application contract" do
    hello = %{"agent_version" => "1.3.0", "auth_token" => "token", "node" => "node-a"}
    assert {:ok, {:hello, ^hello}} = hello |> then(&Contract.encode!(:hello, &1)) |> Contract.decode()
    assert {:error, %NodeWire.Error{}} = Contract.decode(<<4, 10, 131>>)
  end

  test "runtime bundles detect tampering and enforce module policy" do
    modules = runtime_entries()
    bundle = RuntimeBundle.build("1", modules)

    assert :ok = RuntimeBundle.validate(bundle, &(&1 in RuntimeBundle.required_modules()))
    assert {:error, {:module_not_allowed, Exdock.AgentRuntime}} = RuntimeBundle.validate(bundle, fn _ -> false end)

    [{module, _binary, filename} | rest] = modules

    assert {:error, :digest_mismatch} =
             RuntimeBundle.validate(%{bundle | "modules" => [{module, <<4>>, filename} | rest]}, fn _ -> true end)
  end

  test "runtime bundles require every module exactly once" do
    modules = runtime_entries()

    empty_bundle = RuntimeBundle.build("1", [])

    assert {:error, {:runtime_module_set_mismatch, missing, []}} =
             RuntimeBundle.validate(empty_bundle, fn _ -> true end)

    assert MapSet.new(missing) == MapSet.new(RuntimeBundle.required_modules())

    [duplicate | _rest] = modules
    duplicate_bundle = RuntimeBundle.build("1", modules ++ [duplicate])

    assert {:error, {:duplicate_runtime_module, Exdock.AgentRuntime}} =
             RuntimeBundle.validate(duplicate_bundle, fn _ -> true end)

    missing_bundle = RuntimeBundle.build("1", List.delete_at(modules, -1))

    assert {:error, {:runtime_module_set_mismatch, [Exdock.AgentRuntime.Wire], []}} =
             RuntimeBundle.validate(missing_bundle, fn _ -> true end)

    unexpected_bundle =
      RuntimeBundle.build("1", modules ++ [{__MODULE__, <<5>>, ~c"unexpected.beam"}])

    assert {:error, {:runtime_module_set_mismatch, [], [__MODULE__]}} =
             RuntimeBundle.validate(unexpected_bundle, fn _ -> true end)
  end

  test "keeps the runtime module allowlist shared by server and client" do
    assert RuntimeBundle.required_modules() == [
             Exdock.AgentRuntime,
             Exdock.AgentRuntime.Executor,
             Exdock.AgentRuntime.Size,
             Exdock.AgentRuntime.Wire
           ]
  end

  test "keeps command names, internal atoms, and argument contracts in one catalog" do
    for kind <- Command.kinds() do
      assert {:ok, internal} = Command.internal(kind)
      assert {:ok, ^kind} = Command.external(internal)
    end

    assert Command.valid_args?("node_refresh", [%{"retrieve_resources" => true}])
    assert Command.valid_args?(:container_recreate, ["container-id", false])
    refute Command.valid_args?("container_recreate", ["container-id"])
    refute Command.valid_args?("unknown", [])

    assert {:ok,
            %Command.ContainerLogs{
              id: "command-1",
              container_id: "container-id",
              opts: []
            }} = Command.decode(Message.command("command-1", :container_logs, ["container-id"]))

    assert {:error, {:invalid_command_arguments, "container_start"}} =
             Command.decode(%{"id" => "command-2", "kind" => "container_start", "args" => []})
  end

  test "container and image snapshots own their wire round trips" do
    container = %Snapshot.Container{
      name: "web",
      id: "container-id",
      is_running: true,
      stack_name: "app",
      image_tag: "app:latest",
      image_id: "sha256:image",
      inspect: %{State: %{Running: true}},
      resources: nil
    }

    assert {:ok, decoded_container} =
             container
             |> Snapshot.Container.to_wire()
             |> Snapshot.Container.from_wire()

    assert decoded_container.inspect == %{"State" => %{"Running" => true}}

    image = %Snapshot.Image{
      id: "sha256:image",
      name: "app",
      tags: ["app:latest"],
      digest: "sha256:digest",
      size: 10,
      shared_size: 2,
      build_date: ~U[2026-07-29 12:00:00Z]
    }

    assert {:ok, ^image} = image |> Snapshot.Image.to_wire() |> Snapshot.Image.from_wire()
  end

  defp runtime_entries do
    RuntimeBundle.required_modules()
    |> Enum.with_index(1)
    |> Enum.map(fn {module, byte} -> {module, <<byte>>, ~c"runtime.beam"} end)
  end
end
