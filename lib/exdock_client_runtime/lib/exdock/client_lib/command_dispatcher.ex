defmodule Exdock.ClientLib.CommandDispatcher do
  @moduledoc false

  use GenServer

  alias Exdock.ClientLib.CommandRunner
  alias Exdock.Protocol.Message, as: ProtocolMessage
  alias Exdock.Protocol.Messages
  alias Exdock.Protocol.ExecutionBudget

  defstruct node: nil,
            owner: nil,
            executor: nil,
            execution_context: nil,
            wire: nil,
            command_tasks: %{},
            pending_mutations: %{},
            activity_timer: nil,
            accepting?: true

  @type t :: %__MODULE__{
          node: String.t(),
          owner: pid(),
          executor: module(),
          execution_context: term(),
          wire: module(),
          command_tasks: CommandRunner.tasks(),
          pending_mutations: %{String.t() => :queue.queue(map())},
          activity_timer: reference() | nil,
          accepting?: boolean()
        }

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec execute(map(), GenServer.server()) :: :ok
  def execute(command, server \\ __MODULE__), do: GenServer.cast(server, {:execute, command})

  @spec send_update(Messages.Update.t(), GenServer.server()) :: :ok
  def send_update(message, server \\ __MODULE__), do: GenServer.cast(server, {:send_update, message})

  @spec prepare_upgrade(GenServer.server()) :: :ok | {:error, :runtime_busy}
  def prepare_upgrade(server \\ __MODULE__), do: GenServer.call(server, :prepare_upgrade)

  @impl true
  def handle_call(:authorize_command, {pid, _tag}, state) do
    known? = Enum.any?(state.command_tasks, fn {_ref, task} -> task.pid == pid end)
    reply = if state.accepting? and known?, do: :ok, else: {:error, :runtime_upgrading}
    {:reply, reply, state}
  end

  def handle_call(:prepare_upgrade, _from, state) do
    if map_size(state.command_tasks) == 0 and map_size(state.pending_mutations) == 0,
      do: {:reply, :ok, %{state | accepting?: false}},
      else: {:reply, {:error, :runtime_busy}, state}
  end

  @impl true
  def init({node, owner, executor, wire, execution_context}) do
    {:ok,
     %__MODULE__{
       node: node,
       owner: owner,
       executor: executor,
       execution_context: execution_context,
       wire: wire
     }}
  end

  @impl true
  def handle_cast({:execute, %{"id" => id, "kind" => kind}}, %{accepting?: false} = state) do
    publish_result(%{id: id, kind: kind, data: nil, error: :runtime_upgrading}, state)
    {:noreply, state}
  end

  def handle_cast(
        {:execute, %{"id" => _id, "kind" => _kind} = command},
        %__MODULE__{} = state
      ) do
    target = CommandRunner.mutation_target(command)

    if target && Enum.any?(state.command_tasks, fn {_ref, task} -> Map.get(task, :mutation_target) == target end) do
      pending = Map.update(state.pending_mutations, target, :queue.in(command, :queue.new()), &:queue.in(command, &1))
      publish_activity(state, command["id"], command["kind"], "queued")
      {:noreply, ensure_activity_timer(%{state | pending_mutations: pending})}
    else
      {:noreply, start_command(state, command)}
    end
  end

  def handle_cast(
        {:send_update, %Messages.Update{} = message},
        %__MODULE__{node: node, owner: owner} = state
      ) do
    progress = ProtocolMessage.progress(message.id, Atom.to_string(message.name), node, message.data)
    cast_to_server(owner, {:progress, progress})
    {:noreply, state}
  end

  @impl true
  def handle_info({:timeout, ref, :command_activity}, %{activity_timer: ref} = state) do
    for {_ref, task} <- state.command_tasks,
        do: publish_activity(state, task.id, task.kind, "running")

    for {_target, queue} <- state.pending_mutations,
        command <- :queue.to_list(queue),
        do: publish_activity(state, command["id"], command["kind"], "queued")

    {:noreply, ensure_activity_timer(%{state | activity_timer: nil})}
  end

  def handle_info({:timeout, _stale_ref, :command_activity}, state), do: {:noreply, state}

  def handle_info({ref, {data, error}}, %__MODULE__{} = state) when is_reference(ref) do
    complete_command(state, CommandRunner.complete(state.command_tasks, ref, {data, error}))
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %__MODULE__{} = state)
      when is_reference(ref) and is_pid(pid) do
    complete_command(state, CommandRunner.worker_down(state.command_tasks, ref, pid, reason))
  end

  defp complete_command(state, {:ok, command_tasks, outcome}) do
    publish_result(outcome, state)
    {:noreply, %{state | command_tasks: command_tasks} |> start_pending(outcome.mutation_target) |> ensure_activity_timer()}
  end

  defp complete_command(state, :unknown), do: {:noreply, state}

  defp start_command(state, command) do
    publish_activity(state, command["id"], command["kind"], "running")

    %{state | command_tasks: CommandRunner.start(state.command_tasks, command, state.executor, state.execution_context)}
    |> ensure_activity_timer()
  end

  defp ensure_activity_timer(%{command_tasks: tasks, pending_mutations: pending} = state)
       when map_size(tasks) == 0 and map_size(pending) == 0 do
    if state.activity_timer, do: Process.cancel_timer(state.activity_timer)
    %{state | activity_timer: nil}
  end

  defp ensure_activity_timer(%{activity_timer: nil} = state),
    do: %{state | activity_timer: :erlang.start_timer(ExecutionBudget.activity_interval(), self(), :command_activity)}

  defp ensure_activity_timer(state), do: state

  defp publish_activity(state, id, kind, message) do
    cast_to_server(state.owner, {:progress, ProtocolMessage.progress(id, kind, state.node, message)})
  end

  defp start_pending(state, nil), do: state

  defp start_pending(state, target) do
    case Map.pop(state.pending_mutations, target) do
      {nil, _} ->
        state

      {queue, pending} ->
        {{:value, command}, remaining} = :queue.out(queue)
        pending = if :queue.is_empty(remaining), do: pending, else: Map.put(pending, target, remaining)
        start_command(%{state | pending_mutations: pending}, command)
    end
  end

  defp publish_result(%{id: id, kind: kind, data: data, error: error}, state) do
    result =
      ProtocolMessage.result(
        id,
        kind,
        state.node,
        state.wire.encode_result(kind, data),
        state.wire.encode_error(error)
      )

    cast_to_server(state.owner, {:result, result})
  end

  defp cast_to_server(owner, data), do: GenServer.cast(owner, {:client_message, data})
end
