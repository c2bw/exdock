defmodule Exdock.OperationsTest.CastSink do
  @moduledoc false

  use GenServer

  alias Exdock.Events

  def start_link({owner, name}), do: GenServer.start_link(__MODULE__, {owner, name}, name: name)

  @impl true
  def init({owner, name}), do: {:ok, {owner, name}}

  @impl true
  def handle_cast(message, {owner, name} = state) do
    send(owner, {:operation_cast, name, message})
    {:noreply, state}
  end

  @impl true
  def handle_call(message, _from, {owner, name} = state) do
    publish_acceptance(message)
    send(owner, {:operation_call, name, message})
    {:reply, :ok, state}
  end

  defp publish_acceptance({:submit_command, operation_id, _command, opts}),
    do: Events.operation_accepted(operation_id, Keyword.fetch!(opts, :operation_kind))

  defp publish_acceptance({:submit_periodic_job, operation_id}),
    do: Events.operation_accepted(operation_id, :run_automation)

  defp publish_acceptance({:submit_clear_errors, operation_id}),
    do: Events.operation_accepted(operation_id, :clear_errors)
end
