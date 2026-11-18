defmodule Exdock.NativeHandlerTest.Owner do
  use GenServer
  def start_link(test), do: GenServer.start_link(__MODULE__, test)
  def init(test), do: {:ok, test}

  def handle_call({:notify, _, message}, _, test) do
    send(test, {:notification, message})
    {:reply, :ok, test}
  end
end

defmodule Exdock.NativeHandlerTest.Installer do
  use GenServer
  def start_link(test), do: GenServer.start_link(__MODULE__, test, name: Exdock.Client.Connection.RuntimeInstaller)
  def init(test), do: {:ok, %{test: test, result: :ok}}
  def handle_call(:busy, _, s), do: {:reply, :ok, %{s | result: {:error, {:runtime_stop_failed, :runtime_busy}}}}

  def handle_call({:install, _, _, _}, {owner, _}, s) do
    send(s.test, {:install_owner, owner})
    {:reply, s.result, s}
  end
end

defmodule Exdock.NativeHandlerTest.Executor do
  def execute(command), do: send(Exdock.NativeHandlerTest, {:executed, command})
end

defmodule Exdock.NativeHandlerTest do
  use ExUnit.Case, async: false
  alias Exdock.Client.Connection.Native.Handler
  alias Exdock.Protocol.{Message, RuntimeBundle}

  setup do
    Process.register(self(), __MODULE__)
    owner = start_supervised!({__MODULE__.Owner, self()})
    start_supervised!({__MODULE__.Installer, self()})
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: Exdock.Client.Connection.RuntimeBridges})
    start_supervised!({Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor})
    conn = %NodeWire.Conn{owner: owner, id: make_ref(), identity: "node-a"}
    {:ok, state} = Handler.init(%{node: "node-a", token: "token", runtime_executor: __MODULE__.Executor})
    %{conn: conn, state: state, owner: owner}
  end

  test "validates bundles and keeps the installing caller alive as the forwarding owner", %{
    conn: conn,
    state: state,
    owner: owner
  } do
    bundle = RuntimeBundle.build("1", Enum.map(RuntimeBundle.required_modules(), &{&1, <<1>>, ~c"fixture.beam"}))
    assert {:ok, ^bundle} = Handler.validate_message(:runtime_bundle, bundle, conn, state)
    assert {:error, _} = Handler.validate_message(:runtime_bundle, Map.put(bundle, "digest", "bad"), conn, state)
    {:noreply, state} = Handler.handle_message({:runtime_bundle, bundle}, conn, state)
    assert_receive {:install_owner, bridge}
    assert bridge == state.bridge
    assert_receive {:notification, {:runtime_installed, {:ok, ready}}}
    assert ready["digest"] == bundle["digest"]

    assert {:noreply, ^state, [{:send, {:ready, ^ready}}, {:phase, :ready}]} =
             Handler.handle_info({:runtime_installed, {:ok, ready}}, conn, state)

    assert {:ok, ^ready} = Handler.validate_outgoing(:ready, ready, conn, state)
    result = Message.result("job", "node_refresh", "node-a", %{}, nil)
    GenServer.cast(bridge, {:client_message, {:result, result}})
    assert_receive {:notification, {:runtime_message, {:result, ^result}}}

    assert {:noreply, ^state, [{:send, {:result, ^result}}]} =
             Handler.handle_info({:runtime_message, {:result, result}}, conn, state)

    ref = Process.monitor(bridge)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^ref, :process, ^bridge, _}
  end

  test "wrapped runtime busy remains a transient application failure", %{conn: conn, state: state} do
    :ok = GenServer.call(Exdock.Client.Connection.RuntimeInstaller, :busy)
    bundle = RuntimeBundle.build("1", Enum.map(RuntimeBundle.required_modules(), &{&1, <<1>>, ~c"fixture.beam"}))
    {:noreply, _} = Handler.handle_message({:runtime_bundle, bundle}, conn, state)
    assert_receive {:notification, {:runtime_installed, {:error, :runtime_busy}}}
    assert {:stop, :runtime_busy, ^state} = Handler.handle_info({:runtime_installed, {:error, :runtime_busy}}, conn, state)
  end

  test "passes the original validated command map to the runtime", %{conn: conn, state: state} do
    command = Message.command("job", :node_refresh, [%{"retrieve_resources" => false}])
    assert {:ok, ^command} = Handler.validate_message(:command, command, conn, state)
    assert {:noreply, ^state} = Handler.handle_message({:command, command}, conn, state)
    assert_receive {:executed, ^command}
    assert {:error, _} = Handler.validate_message(:command, %{}, conn, state)
    assert {:stop, :installation_failed, ^state} = Handler.handle_info({:runtime_installed, {:error, :bad}}, conn, state)
    assert {:ok, %{"node" => "node-a", "auth_token" => "token"}, ^state} = Handler.handshake_data(conn, state)
  end

  test "outgoing runtime payloads require their existing validators", %{conn: conn, state: state} do
    payloads = [
      progress: Message.progress("j", "node_refresh", "node-a", %{}),
      result: Message.result("j", "node_refresh", "node-a", %{}, nil),
      resource_sample: Message.resource_sample("node-a", "container", %{})
    ]

    for {name, p} <- payloads do
      assert {:ok, ^p} = Handler.validate_outgoing(name, p, conn, state)
      assert {:error, _} = Handler.validate_outgoing(name, %{}, conn, state)
    end

    assert {:error, _} = Handler.validate_outgoing(:unknown, %{}, conn, state)
  end
end
