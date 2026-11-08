defmodule Exdock.Server do
  @moduledoc """
  Central coordinator for the Exdock server runtime.

  This GenServer owns the in-memory server state and exposes the small public API
  used by the web UI, TCP connection handlers, and job orchestration layer. It is
  registered globally so client connection processes and LiveViews can reach the
  same process without carrying its pid around.
  """

  use GenServer
  require Logger
  alias Exdock.Accounts
  alias Exdock.Events
  alias Exdock.Runtime.Command.Executor
  alias Exdock.Runtime.Coordinator
  alias Exdock.Runtime.Query
  alias Exdock.Server.{Automation, ClientIngress, NodeLifecycle}
  alias Exdock.Server.State

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: Coordinator)
  end

  @impl true
  def init(args) do
    email = Keyword.get(args, :email)
    plain_password = Keyword.get(args, :plain_password)

    case Accounts.set_webui_login_credentials(email, plain_password) do
      {:ok, _} ->
        # State creation loads persisted settings/tags and prepares the periodic
        # automation scheduler before clients start reporting node data.
        {:ok, State.create()}

      {:error, e} ->
        Logger.error("Error setting Web UI login credentials: #{inspect(e)}")
        {:stop, :error_webui_credentials_setup}
    end
  end

  # GenServer callbacks keep all state mutation inside the registered server process.

  @impl true
  def handle_call({:query, query}, _from, state), do: {:reply, Query.run(state, query), state}

  @impl true
  def handle_call({:commit_state_change, change}, _from, state) do
    case State.Change.commit(state, change) do
      {:ok, updated_state} -> {:reply, :ok, updated_state}
      {:error, reason, unchanged_state} -> {:reply, {:error, reason}, unchanged_state}
    end
  end

  @impl true
  def handle_call({:submit_command, operation_id, command, opts}, _from, state)
      when is_binary(operation_id) and is_list(opts) do
    kind = Keyword.fetch!(opts, :operation_kind)
    :ok = Events.operation_accepted(operation_id, kind)
    send(self(), {:execute_admitted_command, operation_id, command, opts})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:submit_periodic_job, operation_id}, _from, %State{} = state)
      when is_binary(operation_id) do
    :ok = Events.operation_accepted(operation_id, :run_automation)
    send(self(), {:execute_admitted_periodic_job, operation_id})
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:connections_reset, state), do: {:noreply, NodeLifecycle.reset(state)}

  @impl true
  def handle_cast({:node_is_up, node, metadata}, state) when is_binary(node) and is_map(metadata) do
    {:noreply, NodeLifecycle.connected(state, node, metadata)}
  end

  @impl true
  def handle_cast({:node_is_down, node}, state) when is_binary(node) do
    {:noreply, NodeLifecycle.disconnected(state, node)}
  end

  @impl true
  def handle_cast({:state_change, change}, state), do: {:noreply, State.Change.change(state, change)}
  @impl true
  def handle_cast({:client_message, handler, client_name, message}, state),
    do: {:noreply, ClientIngress.accept(state, client_name, handler, message)}

  @impl true
  def handle_cast({:command, operation_id, command, opts}, state) when is_list(opts) do
    {:noreply, Executor.execute(state, operation_id, command, opts)}
  end

  @impl true
  def handle_cast({:run_periodic_job}, %State{} = state) do
    {:noreply, Automation.run(state, nil)}
  end

  @impl true
  def handle_cast({:run_periodic_job, operation_id}, %State{} = state)
      when is_binary(operation_id) do
    {:noreply, Automation.run(state, operation_id)}
  end

  @impl true
  def handle_cast({:change_periodic_job, cron}, %State{} = state) when is_binary(cron) do
    {:noreply, Automation.change_schedule(state, cron)}
  end

  @impl true
  def handle_info({:delayed_command, operation_id, command, opts}, state) when is_list(opts) do
    {:noreply, Executor.execute(state, operation_id, command, opts)}
  end

  @impl true
  def handle_info({:execute_admitted_command, operation_id, command, opts}, state)
      when is_binary(operation_id) and is_list(opts) do
    case Keyword.get(opts, :delay, 0) do
      delay when is_integer(delay) and delay > 0 ->
        Process.send_after(self(), {:delayed_command, operation_id, command, opts}, delay)
        {:noreply, state}

      _delay ->
        {:noreply, Executor.execute(state, operation_id, command, opts)}
    end
  end

  @impl true
  def handle_info({:execute_admitted_periodic_job, operation_id}, %State{} = state)
      when is_binary(operation_id) do
    {:noreply, Automation.run(state, operation_id)}
  end
end
