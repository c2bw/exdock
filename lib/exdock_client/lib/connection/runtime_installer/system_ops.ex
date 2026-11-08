defmodule Exdock.Client.Connection.RuntimeInstaller.SystemOps do
  @moduledoc false

  @behaviour Exdock.Client.Connection.RuntimeInstaller.Ops

  @impl true
  def beam_exports(binary), do: :beam_lib.chunks(binary, [:exports])

  @impl true
  def object_code(module), do: :code.get_object_code(module)

  @impl true
  def load_binary(module, filename, binary), do: :code.load_binary(module, filename, binary)

  @impl true
  def purge(module), do: :code.purge(module)

  @impl true
  def delete(module), do: :code.delete(module)

  @impl true
  def whereis(name), do: Process.whereis(name)

  @impl true
  def stop(pid, timeout), do: GenServer.stop(pid, :normal, timeout)

  # Command registrations survive dispatcher replacement. Resource samples and
  # unrelated base-client tasks must not hold runtime installation open.
  @impl true
  def prepare_upgrade do
    if Registry.count_select(Exdock.AgentRegistry, [{{{:command_worker, :_}, :_, :_}, [], [true]}]) > 0 do
      {:error, :runtime_busy}
    else
      case Process.whereis(Exdock.ClientLib.CommandDispatcher) do
        nil -> :ok
        dispatcher -> Exdock.ClientLib.CommandDispatcher.prepare_upgrade(dispatcher)
      end
    end
  end

  @impl true
  def start(runtime_module, args), do: runtime_module.start_link(args)
end
