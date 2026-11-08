defmodule Exdock.Server.Jobs.Supervisor do
  @moduledoc """
  Owns the job engine and every local worker it dispatches.

  A one-for-all strategy keeps worker lifetime coupled to authoritative job
  state: restarting either the engine or its task supervisor terminates the
  whole subtree before accepting more work.
  """

  use Supervisor

  alias Exdock.Server.Jobs

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :supervisor_name, __MODULE__)
    start_opts = if is_nil(name), do: [], else: [name: name]
    Supervisor.start_link(__MODULE__, init_opts, start_opts)
  end

  @impl true
  def init(opts) do
    {task_supervisor, jobs_opts} = Keyword.pop(opts, :task_supervisor, Jobs.TaskSupervisor)

    children = [
      Supervisor.child_spec({Task.Supervisor, name: task_supervisor}, id: task_supervisor),
      {Jobs, Keyword.put(jobs_opts, :task_supervisor, task_supervisor)}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
