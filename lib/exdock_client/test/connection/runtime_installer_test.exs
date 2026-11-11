defmodule Exdock.Client.Connection.RuntimeInstallerTest do
  use ExUnit.Case, async: false

  alias Exdock.Client.Connection.{Protocol, RuntimeInstaller}
  alias Exdock.Protocol.{Contract, RuntimeBundle}

  setup do
    start_supervised!({Registry, keys: :unique, name: Exdock.AgentRegistry})
    start_supervised!(RuntimeInstaller)
    :ok
  end

  test "accepts only the fixed agent runtime module set" do
    assert RuntimeInstaller.allowed_module?(Exdock.AgentRuntime)
    assert RuntimeInstaller.allowed_module?(Exdock.AgentRuntime.Executor)
    assert RuntimeInstaller.allowed_module?(Exdock.AgentRuntime.Size)
    assert RuntimeInstaller.allowed_module?(Exdock.AgentRuntime.Wire)
    refute RuntimeInstaller.allowed_module?(Exdock.AgentRuntime.Unexpected)
    refute RuntimeInstaller.allowed_module?(Exdock.Client.Connection.TCPClient)
    refute RuntimeInstaller.allowed_module?("Elixir.Exdock.AgentRuntime")
  end

  test "rejects malformed and disallowed bundles before loading code" do
    assert {:error, :invalid_runtime_bundle} =
             RuntimeInstaller.install(%{}, "node-a", Exdock.AgentRuntime)

    bundle =
      RuntimeBundle.build("1", [
        {Exdock.Client.Connection.TCPClient, <<1, 2, 3>>, ~c"tcp_client.beam"}
      ])

    assert {:error, {:module_not_allowed, Exdock.Client.Connection.TCPClient}} =
             RuntimeInstaller.install(bundle, "node-a", Exdock.AgentRuntime)
  end

  test "reports load failures with the rejected module" do
    modules =
      Enum.map(RuntimeBundle.required_modules(), fn module ->
        {module, <<1, 2, 3>>, ~c"invalid.beam"}
      end)

    bundle = RuntimeBundle.build("1", modules)

    assert {:error, {:invalid_beam, Exdock.AgentRuntime, _reason}} =
             RuntimeInstaller.install(bundle, "node-a", Exdock.AgentRuntime)
  end

  test "preflights the embedded BEAM module identity before loading any entry" do
    {RuntimeInstaller, binary, filename} = :code.get_object_code(RuntimeInstaller)

    modules =
      Enum.map(RuntimeBundle.required_modules(), fn module ->
        {module, binary, filename}
      end)

    bundle = RuntimeBundle.build("1", modules)

    assert {:error, {:module_name_mismatch, Exdock.AgentRuntime, RuntimeInstaller}} =
             RuntimeInstaller.install(bundle, "node-a", Exdock.AgentRuntime)
  end

  test "failed runtime replacement restores all prior modules and restarts the old runtime" do
    clean_runtime_on_exit()
    previous = compile_runtime(:previous, :start)
    replacement = compile_runtime(:replacement, :reject_start)
    unload_runtime_modules()

    assert :ok =
             "1"
             |> RuntimeBundle.build(previous)
             |> RuntimeInstaller.install("node-a", Exdock.AgentRuntime)

    previous_pid = Process.whereis(Exdock.ClientLib)
    assert apply(Exdock.AgentRuntime, :version, []) == :previous
    %{installed_modules: installed_snapshot} = :sys.get_state(RuntimeInstaller)

    bundle = RuntimeBundle.build("2", replacement)

    assert {:error, {:runtime_start_failed, :upgrade_rejected}} =
             RuntimeInstaller.install(bundle, "node-a", Exdock.AgentRuntime)

    restarted_pid = Process.whereis(Exdock.ClientLib)
    assert is_pid(restarted_pid)
    refute restarted_pid == previous_pid
    assert apply(Exdock.AgentRuntime, :version, []) == :previous
    assert Agent.get(restarted_pid, & &1) == {:previous, self()}
    assert %{installed_modules: ^installed_snapshot} = :sys.get_state(RuntimeInstaller)
  end

  test "reports an unavailable installation coordinator" do
    assert {:error, {:installer_unavailable, :not_found}} =
             RuntimeInstaller.install(%{}, "node-a", Exdock.AgentRuntime, :missing_runtime_installer)
  end

  for runtime_present? <- [true, false] do
    @runtime_present runtime_present?
    test "active base-client work defers replacement when runtime present is #{runtime_present?}" do
      clean_runtime_on_exit()
      previous = compile_runtime(:previous, :start)
      replacement = compile_runtime(:replacement, :start)
      unload_runtime_modules()
      start_supervised!({Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor})
      assert :ok = RuntimeInstaller.install(RuntimeBundle.build("1", previous), "node-a")
      previous_pid = Process.whereis(Exdock.ClientLib)
      owner = self()

      task =
        Task.Supervisor.async_nolink(Exdock.Client.Connection.TaskSupervisor, fn ->
          {:ok, _} = Registry.register(Exdock.AgentRegistry, {:command_worker, self()}, nil)
          send(owner, :worker_started)

          receive do
            :finish -> :ok
          end
        end)

      assert_receive :worker_started

      unless @runtime_present do
        GenServer.stop(previous_pid, :normal)
      end

      bundle = RuntimeBundle.build("2", replacement)
      assert {:error, {:runtime_stop_failed, :runtime_busy}} = RuntimeInstaller.install(bundle, "node-a")
      assert Process.whereis(Exdock.ClientLib) == if(@runtime_present, do: previous_pid, else: nil)
      assert apply(Exdock.AgentRuntime, :version, []) == :previous
      send(task.pid, :finish)
      assert Task.await(task) == :ok
      assert :ok = RuntimeInstaller.install(bundle, "node-a")
      assert apply(Exdock.AgentRuntime, :version, []) == :replacement
    end
  end

  test "background sampling work does not prevent runtime replacement" do
    clean_runtime_on_exit()
    previous = compile_runtime(:previous, :start)
    replacement = compile_runtime(:replacement, :start)
    unload_runtime_modules()
    start_supervised!({Task.Supervisor, name: Exdock.Client.Connection.TaskSupervisor})
    assert :ok = RuntimeInstaller.install(RuntimeBundle.build("1", previous), "node-a")
    owner = self()

    task =
      Task.Supervisor.async_nolink(Exdock.Client.Connection.TaskSupervisor, fn ->
        send(owner, :background_started)

        receive do
          :finish -> :ok
        end
      end)

    assert_receive :background_started
    assert :ok = RuntimeInstaller.install(RuntimeBundle.build("2", replacement), "node-a")
    assert apply(Exdock.AgentRuntime, :version, []) == :replacement
    send(task.pid, :finish)
    assert Task.await(task) == :ok
  end

  test "preflight failure leaves the existing runtime untouched" do
    clean_runtime_on_exit()
    previous = compile_runtime(:previous, :start)
    replacement = compile_runtime(:replacement, :start)
    unload_runtime_modules()

    assert :ok =
             "1"
             |> RuntimeBundle.build(previous)
             |> RuntimeInstaller.install("node-a", Exdock.AgentRuntime)

    previous_pid = Process.whereis(Exdock.ClientLib)

    invalid_replacement =
      List.update_at(replacement, -1, fn {module, _binary, filename} ->
        {module, <<1, 2, 3>>, filename}
      end)

    bundle = RuntimeBundle.build("2", invalid_replacement)

    assert {:error, {:invalid_beam, Exdock.AgentRuntime.Wire, _reason}} =
             RuntimeInstaller.install(bundle, "node-a", Exdock.AgentRuntime)

    assert Process.whereis(Exdock.ClientLib) == previous_pid
    assert apply(Exdock.AgentRuntime, :version, []) == :previous
  end

  test "successful runtime replacement stops the old runtime before switching every module" do
    clean_runtime_on_exit()
    previous = compile_runtime(:previous, :start)
    replacement = compile_runtime(:replacement, :start)
    unload_runtime_modules()

    assert :ok =
             "1"
             |> RuntimeBundle.build(previous)
             |> RuntimeInstaller.install("node-a", Exdock.AgentRuntime)

    previous_pid = Process.whereis(Exdock.ClientLib)

    bundle = RuntimeBundle.build("2", replacement)
    frame = Contract.encode!(:runtime_bundle, bundle)
    assert {:runtime_bundle, decoded} = Protocol.decode_message(frame)
    assert :ok = RuntimeInstaller.install(decoded, "node-a", Exdock.AgentRuntime)

    replacement_pid = Process.whereis(Exdock.ClientLib)
    assert is_pid(replacement_pid)
    refute replacement_pid == previous_pid
    assert apply(Exdock.AgentRuntime, :version, []) == :replacement
    assert Agent.get(replacement_pid, & &1) == {:replacement, self()}
  end

  defp compile_runtime(version, start_mode) do
    compiler_options = Code.compiler_options()
    Code.compiler_options(ignore_module_conflict: true)

    try do
      RuntimeBundle.required_modules()
      |> Enum.map(fn module -> compile_module(module, version, start_mode) end)
    after
      Code.compiler_options(compiler_options)
    end
  end

  defp compile_module(Exdock.AgentRuntime = module, version, start_mode) do
    {owner_pattern, start_link} =
      case start_mode do
        :start ->
          {"owner", "Agent.start_link(fn -> {#{inspect(version)}, owner} end, name: Exdock.ClientLib)"}

        :reject_start ->
          {"_owner", "{:error, :upgrade_rejected}"}
      end

    source = """
      defmodule #{inspect(module)} do
        def version, do: #{inspect(version)}
        def start_link({_node, #{owner_pattern}}), do: #{start_link}
      def execute(_command), do: :ok
    end
    """

    compile_entry(module, source, version)
  end

  defp compile_module(module, version, _start_mode) do
    source = """
    defmodule #{inspect(module)} do
      def version, do: #{inspect(version)}
    end
    """

    compile_entry(module, source, version)
  end

  defp compile_entry(module, source, version) do
    [{^module, binary}] = Code.compile_string(source, "#{module}.#{version}.ex")
    {module, binary, String.to_charlist("#{module}.#{version}.beam")}
  end

  defp unload_runtime_modules do
    Enum.each(RuntimeBundle.required_modules(), fn module ->
      :code.purge(module)
      :code.delete(module)
      :code.purge(module)
    end)
  end

  defp clean_runtime_on_exit do
    on_exit(fn ->
      if pid = Process.whereis(Exdock.ClientLib) do
        try do
          GenServer.stop(pid, :normal)
        catch
          :exit, {:noproc, _call} -> :ok
        end
      end

      Enum.each(RuntimeBundle.required_modules(), fn module ->
        :code.purge(module)
        :code.delete(module)
        :code.purge(module)
      end)
    end)
  end
end
