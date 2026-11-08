defmodule Exdock.Server.JobsTest.CommandSink do
  @moduledoc false

  use GenServer

  def start_link(owner), do: GenServer.start_link(__MODULE__, owner)

  @impl true
  def init({owner, reply}), do: {:ok, %{owner: owner, reply: reply}}
  def init(owner), do: {:ok, %{owner: owner, reply: :ok}}

  @impl true
  def handle_call({:send_command, node, job}, _from, %{owner: owner, reply: reply} = state) do
    send(owner, {:command_sink, node, job})
    {:reply, reply, state}
  end
end
