defmodule Exdock.ClientLib.CommandRunner do
  @moduledoc """
  Owns supervised command execution and command-task correlation.

  The client GenServer remains responsible for publishing protocol results.
  This module starts workers, normalizes executor failures, and resolves worker
  messages back to the command metadata needed by that transport boundary.
  """

  require Logger
  alias Exdock.ClientLib.Execution
  alias Exdock.ClientLib.CommandLock
  alias Exdock.ClientLib.Jobs.Context

  @task_supervisor Exdock.Client.Connection.TaskSupervisor

  @type task_info :: %{
          required(:id) => String.t(),
          required(:kind) => String.t(),
          required(:pid) => pid(),
          optional(:mutation_target) => String.t() | nil
        }
  @type tasks :: %{optional(reference()) => task_info()}
  @type outcome :: %{id: String.t(), kind: String.t(), data: term(), error: term(), mutation_target: String.t() | nil}

  @spec start(tasks(), map(), module(), term()) :: tasks()
  def start(tasks, %{"id" => id, "kind" => kind} = command, executor, execution_context)
      when is_map(tasks) and is_atom(executor) do
    owner = self()

    task =
      Task.Supervisor.async_nolink(
        @task_supervisor,
        fn -> execute_owned(owner, command, executor, execution_context) end
      )

    Map.put(tasks, task.ref, %{id: id, kind: kind, pid: task.pid, mutation_target: mutation_target(command)})
  end

  defp execute_owned(owner, command, executor, execution_context) do
    key = {:command_worker, self()}
    {:ok, _} = Registry.register(Exdock.AgentRegistry, key, nil)

    try do
      # Registration precedes admission. If the dispatcher died before tracking
      # this worker, it cannot enter replaceable runtime code or touch Docker.
      case GenServer.call(owner, :authorize_command, :infinity) do
        :ok -> CommandLock.run(mutation_target(command), fn -> execute_safely(command, executor, execution_context) end)
        {:error, reason} -> {nil, reason}
      end
    catch
      :exit, _reason -> {nil, :command_owner_unavailable}
    after
      Registry.unregister(Exdock.AgentRegistry, key)
    end
  end

  @doc "Container mutations use the stable container name sent by the server."
  @spec mutation_target(map()) :: String.t() | nil
  def mutation_target(%{"kind" => kind, "args" => [target | _]})
      when kind in ["container_start", "container_stop", "container_restart", "container_recreate"] and is_binary(target),
      do: String.trim_leading(target, "/")

  def mutation_target(_command), do: nil

  @spec complete(tasks(), reference(), {term(), term()}) ::
          {:ok, tasks(), outcome()} | :unknown
  def complete(tasks, ref, {data, error}) when is_map(tasks) and is_reference(ref) do
    case Map.pop(tasks, ref) do
      {%{id: id, kind: kind} = task, remaining_tasks} ->
        Process.demonitor(ref, [:flush])

        {:ok, remaining_tasks, %{id: id, kind: kind, data: data, error: error, mutation_target: Map.get(task, :mutation_target)}}

      {nil, _remaining_tasks} ->
        :unknown
    end
  end

  @spec worker_down(tasks(), reference(), pid(), term()) ::
          {:ok, tasks(), outcome()} | :unknown
  def worker_down(tasks, ref, pid, reason)
      when is_map(tasks) and is_reference(ref) and is_pid(pid) do
    case Map.pop(tasks, ref) do
      {%{id: id, kind: kind, pid: ^pid} = task, remaining_tasks} ->
        Logger.error("Agent command worker exited: #{inspect(reason)}")

        {:ok, remaining_tasks,
         %{
           id: id,
           kind: kind,
           data: nil,
           error: {:command_worker_exit, inspect(reason)},
           mutation_target: Map.get(task, :mutation_target)
         }}

      {_unknown_task, _remaining_tasks} ->
        :unknown
    end
  end

  @spec execute_safely(map(), module(), term()) :: {term(), term()}
  def execute_safely(command, executor, execution_context)
      when is_map(command) and is_atom(executor) do
    result =
      case execution_context do
        %Context{} = context ->
          command
          |> Execution.wrap(context)
          |> executor.execute()

        _other ->
          executor.execute(command)
      end

    case result do
      {:ok, data} -> {data, nil}
      {:error, error, data} -> {data, error}
    end
  rescue
    exception ->
      Logger.error("Agent command crashed: #{Exception.format(:error, exception, __STACKTRACE__)}")
      {nil, {:exception, Exception.message(exception)}}
  catch
    kind, reason ->
      Logger.error("Agent command exited: #{Exception.format_banner(kind, reason)}")
      {nil, {kind, inspect(reason)}}
  end
end
