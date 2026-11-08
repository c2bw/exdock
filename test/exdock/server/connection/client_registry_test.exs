defmodule Exdock.Server.Connection.TCPServer.ClientRegistryTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Connection.TCPServer.ClientRegistry

  setup do
    registry = start_supervised!({ClientRegistry, name: nil})
    %{registry: registry}
  end

  test "registers and fetches a validated client", %{registry: registry} do
    handler = self()

    assert :ok = ClientRegistry.register("node-a", handler, registry)
    assert ClientRegistry.fetch("node-a", registry) == {:ok, handler}
    assert ClientRegistry.connected_clients(registry) == %{"node-a" => handler}
  end

  test "rejects duplicate and invalid client identities", %{registry: registry} do
    assert :ok = ClientRegistry.register("node-a", self(), registry)
    assert ClientRegistry.register("node-a", self(), registry) == {:error, :duplicate}
    assert ClientRegistry.register("has spaces", self(), registry) == {:error, :invalid}
    assert ClientRegistry.register(:not_a_string, self(), registry) == {:error, :invalid}
  end

  test "unregisters only the matching handler", %{registry: registry} do
    handler = self()
    other_handler = spawn(fn -> receive do: (:stop -> :ok) end)

    assert :ok = ClientRegistry.register("node-a", handler, registry)
    assert :ok = ClientRegistry.unregister("node-a", other_handler, registry)
    assert ClientRegistry.fetch("node-a", registry) == {:ok, handler}

    assert :ok = ClientRegistry.unregister("node-a", handler, registry)
    assert ClientRegistry.fetch("node-a", registry) == :error

    send(other_handler, :stop)
  end

  test "automatically releases a client when its handler exits", %{registry: registry} do
    handler = spawn(fn -> receive do: (:stop -> :ok) end)
    handler_monitor = Process.monitor(handler)

    assert :ok = ClientRegistry.register("node-a", handler, registry)
    send(handler, :stop)
    assert_receive {:DOWN, ^handler_monitor, :process, ^handler, :normal}

    _ = :sys.get_state(registry)
    assert ClientRegistry.fetch("node-a", registry) == :error
  end
end
