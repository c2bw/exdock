defmodule ExdockWeb.LiveCase.TestServer do
  @moduledoc false

  use GenServer

  alias Exdock.Events
  alias Exdock.Runtime.Command.Executor
  alias Exdock.Runtime.Query
  alias Exdock.Server.State
  alias Exdock.Server.State.Storage

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: Exdock.Runtime.Coordinator)

  @impl true
  def init(_opts) do
    {:ok, State.create()}
  end

  @impl true
  def handle_call({:query, query}, _from, %State{} = state) do
    {:reply, Query.run(state, query), state}
  end

  def handle_call({:commit_state_change, change}, _from, %State{} = state) do
    case State.Change.commit(state, change) do
      {:ok, updated_state} -> {:reply, :ok, updated_state}
      {:error, reason, unchanged_state} -> {:reply, {:error, reason}, unchanged_state}
    end
  end

  def handle_call({:submit_command, operation_id, command, opts}, _from, %State{} = state)
      when is_binary(operation_id) and is_list(opts) do
    :ok = Events.operation_accepted(operation_id, Keyword.fetch!(opts, :operation_kind))

    state =
      case Keyword.get(opts, :delay, 0) do
        delay when is_integer(delay) and delay > 0 ->
          Process.send_after(self(), {:delayed_command, operation_id, command, opts}, delay)
          state

        _delay ->
          Executor.execute(state, operation_id, command, opts)
      end

    {:reply, :ok, state}
  end

  def handle_call({:submit_periodic_job, operation_id}, _from, %State{} = state)
      when is_binary(operation_id) do
    :ok = Events.operation_accepted(operation_id, :run_automation)
    {:noreply, state} = run_periodic_job(state, operation_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:state_change, change}, %State{} = state) do
    {:noreply, State.Change.change(state, change)}
  end

  def handle_cast({:node_is_up, node, metadata}, %State{} = state) when is_binary(node) and is_map(metadata) do
    node = Exdock.NodeId.normalize!(node)

    case State.nodeup(state, node, metadata) |> State.Transition.commit() do
      {:ok, state} -> {:noreply, state}
      {:error, _reason, unchanged_state} -> {:noreply, unchanged_state}
    end
  end

  def handle_cast({:node_is_down, node}, %State{} = state) when is_binary(node) do
    node = Exdock.NodeId.normalize!(node)
    {state, effects} = State.nodedown(state, node)
    :ok = State.EffectExecutor.run(state, effects)
    {:noreply, state}
  end

  def handle_cast({:command, operation_id, command, opts}, %State{} = state) when is_list(opts) do
    {:noreply, Executor.execute(state, operation_id, command, opts)}
  end

  def handle_cast({:run_periodic_job}, %State{} = state) do
    run_periodic_job(state, nil)
  end

  def handle_cast({:run_periodic_job, operation_id}, %State{} = state)
      when is_binary(operation_id) do
    run_periodic_job(state, operation_id)
  end

  def handle_cast({:change_periodic_job, cron}, %State{} = state) when is_binary(cron) do
    change = Exdock.Runtime.Mutation.user_setting!(:cron_string, cron)
    {:noreply, State.Change.change(state, change)}
  end

  @impl true
  def handle_info({:delayed_command, operation_id, command, opts}, %State{} = state)
      when is_list(opts) do
    {:noreply, Executor.execute(state, operation_id, command, opts)}
  end

  defp run_periodic_job(%State{} = state, operation_id) do
    settings = Storage.Settings.get(state.settings)

    if settings.automation_enabled do
      if settings.auto_update_containers do
        Exdock.Runtime.Coordinator.command(nil, State.Jobs.compose(:containers_update))
      else
        Exdock.Runtime.Coordinator.command(nil, State.Jobs.compose(:registry_update))
      end
    end

    finish_operation(operation_id, :run_automation, %{status: :completed})
    {:noreply, State.periodic_job_rollover(state)}
  end

  defp finish_operation(nil, _kind, _result), do: :ok

  defp finish_operation(operation_id, kind, result), do: Events.operation_finished(operation_id, kind, result)
end
