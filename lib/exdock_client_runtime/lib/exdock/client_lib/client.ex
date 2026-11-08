defmodule Exdock.ClientLib do
  @moduledoc """
  Stable facade and supervision boundary for node-side runtime work.

  Commands and progress updates are owned by `CommandDispatcher`; periodic
  resource batches are owned by `AsyncBatchScheduler`. Keeping those mailboxes
  separate prevents long command bursts from delaying polling state changes.
  """

  use Supervisor

  alias Exdock.ClientLib.{Async, AsyncBatchScheduler, CommandDispatcher}
  alias Exdock.ClientLib.Jobs.Context
  alias Exdock.Protocol.Messages

  @doc "Starts the client runtime and links its lifecycle to the connection owner."
  def start_link(args, opts \\ []) do
    Supervisor.start_link(__MODULE__, args, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init({node, owner, executor, wire})
      when is_binary(node) and is_pid(owner) and is_atom(executor) and is_atom(wire) do
    init({node, owner, executor, wire, Context.runtime()})
  end

  def init({node, owner, executor, wire, execution_context})
      when is_binary(node) and is_pid(owner) and is_atom(executor) and is_atom(wire) do
    true = Process.link(owner)

    children = [
      {CommandDispatcher, {node, owner, executor, wire, execution_context}},
      {AsyncBatchScheduler, {node, owner, wire}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Executes one validated protocol command through the fixed agent executor."
  @spec execute_command(map()) :: :ok
  def execute_command(command) when is_map(command), do: CommandDispatcher.execute(command)

  @doc "Adds a batch of asynchronous resource-sampling jobs."
  @spec add_async_batch(Async.Batch.t()) :: :ok
  def add_async_batch(%Async.Batch{} = batch), do: AsyncBatchScheduler.add(batch)

  @doc "Sends a mid-job update to the server."
  @spec send_job_update(Messages.Update.t(), GenServer.server()) :: :ok
  def send_job_update(%Messages.Update{} = message, dispatcher \\ CommandDispatcher),
    do: CommandDispatcher.send_update(message, dispatcher)

  @spec send_job_update_message(String.t(), atom(), String.t(), GenServer.server()) :: :ok
  def send_job_update_message(job_id, job_name, message, dispatcher \\ CommandDispatcher)
      when is_binary(job_id) and is_atom(job_name) and is_binary(message) do
    send_job_update(Messages.Update.new(job_id, job_name, message), dispatcher)
  end
end
