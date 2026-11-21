defmodule Exdock.NativeHandlerTest.Owner do
  use NodeWire.Handler
  def init(test), do: {:ok, test}
  def handshake_data(_, test), do: {:ok, %{}, test}
  def authenticate(_, _, test), do: {:ok, "node-a", test}
  def validate_message(_, payload, _, _), do: {:ok, payload}

  def handle_negotiated(%{role: :client} = conn, test) do
    send(test, {:owner_connection, conn})
    {:noreply, test}
  end

  def handle_negotiated(_, test), do: {:noreply, test}

  def handle_message(message, _, test) do
    send(test, {:wire_message, message})
    {:noreply, test}
  end

  def handle_info(message, _, test) do
    send(test, {:notification, message})
    {:noreply, test}
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
    fixtures = Path.expand("../../../../test/fixtures/nodewire", __DIR__)
    names = Map.keys(Exdock.Wire.V1.message_types())
    phases = [initial: :ready, ready: :ready, states: %{ready: %{incoming: names, outgoing: names, next: []}}]

    server =
      start_supervised!(
        {NodeWire.Server,
         protocols: [Exdock.Wire.V1],
         handler: __MODULE__.Owner,
         handler_args: self(),
         phases: phases,
         transport:
           {:tls,
            [
              port: 0,
              options: [
                certfile: String.to_charlist(fixtures <> "/server.pem"),
                keyfile: String.to_charlist(fixtures <> "/server.key")
              ]
            ]}}
      )

    client =
      start_supervised!(
        {NodeWire.Client,
         protocols: [Exdock.Wire.V1],
         handler: __MODULE__.Owner,
         handler_args: self(),
         phases: phases,
         reconnect: [enabled: false],
         limits: [max_pending_messages: 1],
         transport:
           {:tls,
            [
              host: "localhost",
              port: NodeWire.Server.port(server),
              options: [verify: :verify_peer, cacertfile: String.to_charlist(fixtures <> "/ca.pem")]
            ]}}
      )

    assert_receive {:owner_connection, conn}, 2000
    owner = conn.owner
    start_supervised!({__MODULE__.Installer, self()})
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: Exdock.Client.Connection.RuntimeBridges})
    start_supervised!({Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor})
    {:ok, state} = Handler.init(%{node: "node-a", token: "token", runtime_executor: __MODULE__.Executor})
    %{conn: conn, state: state, owner: owner, client: client}
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

  test "overload retains the latest sample and flushes it on the same connection", %{conn: conn, state: state} do
    bridge = start_bridge(conn, state)
    token = reserve(conn)
    first = Message.resource_sample("node-a", "container", %{"sequence" => 1})
    latest = Message.resource_sample("node-a", "container", %{"sequence" => 2})
    GenServer.cast(bridge, {:client_message, {:resource_sample, first}})
    GenServer.cast(bridge, {:client_message, {:resource_sample, latest}})
    assert :sys.get_state(bridge).pending_resources == %{"container" => latest}
    NodeWire.Admission.release(conn.admission, token)

    assert_receive {:notification, {:runtime_message, {:resource_sample, ^latest}}}, 1000
    refute_receive {:notification, {:runtime_message, {:resource_sample, ^first}}}, 50
    assert :sys.get_state(bridge).pending_resources == %{}
  end

  test "deferred samples have count and byte bounds", %{conn: conn, state: state} do
    bridge = start_bridge(conn, state)
    token = reserve(conn)

    oversized = Message.resource_sample("node-a", "large", %{"data" => String.duplicate("x", 1_048_576)})
    GenServer.cast(bridge, {:client_message, {:resource_sample, oversized}})
    assert :sys.get_state(bridge).pending_resources == %{}

    for id <- 1..65 do
      sample = Message.resource_sample("node-a", Integer.to_string(id), %{})
      GenServer.cast(bridge, {:client_message, {:resource_sample, sample}})
    end

    assert map_size(:sys.get_state(bridge).pending_resources) == 64
    refute Map.has_key?(:sys.get_state(bridge).pending_resources, "65")
    GenServer.stop(bridge)
    NodeWire.Admission.release(conn.admission, token)
  end

  test "a notification timeout keeps the bridge alive and does not replay its payload", %{conn: conn, state: state} do
    bridge = start_bridge(conn, state)
    token = reserve(conn)
    NodeWire.Admission.release(conn.admission, token)
    :sys.suspend(conn.owner)
    on_exit(fn -> resume(conn.owner) end)
    monitor = Process.monitor(bridge)
    sample = Message.resource_sample("node-a", "slow-container", %{})
    GenServer.cast(bridge, {:client_message, {:resource_sample, sample}})
    assert :sys.get_state(bridge, 6000).pending_resources == %{}
    refute_received {:DOWN, ^monitor, :process, ^bridge, _}
    :sys.resume(conn.owner)
    assert_receive {:notification, {:runtime_message, {:resource_sample, ^sample}}}, 1000
    refute_receive {:notification, {:runtime_message, {:resource_sample, ^sample}}}, 50
  end

  test "critical job overload closes the session for recovery", %{conn: conn, state: state} do
    bridge = start_bridge(conn, state)
    _token = reserve(conn)
    monitor = Process.monitor(conn.owner)
    result = Message.result("job", "container_start", "node-a", "container", nil)
    GenServer.cast(bridge, {:client_message, {:result, result}})
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    refute_receive {:notification, {:runtime_message, {:result, ^result}}}, 50
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

  defp start_bridge(conn, state) do
    bundle = RuntimeBundle.build("1", Enum.map(RuntimeBundle.required_modules(), &{&1, <<1>>, ~c"fixture.beam"}))
    {:noreply, next} = Handler.handle_message({:runtime_bundle, bundle}, conn, state)
    assert_receive {:notification, {:runtime_installed, {:ok, _}}}
    next.bridge
  end

  defp reserve(conn, attempts \\ 100)
  defp reserve(_conn, 0), do: flunk("Admission remained busy during setup")

  defp reserve(conn, attempts) do
    case NodeWire.Admission.checkout(conn.admission, 1) do
      {:ok, token, _} ->
        token

      _ ->
        receive do
        after
          10 -> reserve(conn, attempts - 1)
        end
    end
  end

  defp resume(owner) do
    :sys.resume(owner)
  catch
    :exit, _ -> :ok
  end
end
