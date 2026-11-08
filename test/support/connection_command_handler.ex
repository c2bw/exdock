defmodule Exdock.TestSupport.ConnectionCommandHandler do
  @moduledoc false
  use GenServer, restart: :temporary

  alias Exdock.Server.Connection.TCPServer.ClientRegistry

  def start_link(mode), do: GenServer.start_link(__MODULE__, mode)
  def init(mode), do: {:ok, mode}

  def handle_call({:send_command, _job}, _from, :timeout = mode), do: {:noreply, mode}

  def handle_call({:send_command, job}, _from, {:accept, owner} = mode) do
    send(owner, {:command_accepted, job})
    {:reply, :ok, mode}
  end

  def handle_call({:send_command, _job}, _from, {:replace, registry, replacement} = mode) do
    :ok = ClientRegistry.unregister("node-a", self(), registry)
    :ok = ClientRegistry.register("node-a", replacement, registry)
    {:reply, {:error, :closed}, mode}
  end
end
