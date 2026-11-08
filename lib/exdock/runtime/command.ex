defmodule Exdock.Runtime.Command do
  @moduledoc false

  alias Exdock.Runtime.Command
  alias Exdock.Runtime.Command.MutationExecutor
  alias Exdock.Runtime.Mutation
  alias Exdock.Server.State
  alias Exdock.Server.Jobs.Plan

  @typed_handlers [
    Command.Cluster,
    Command.Image,
    Command.Container,
    Command.Repository,
    Command.Settings.Image,
    Command.Settings.Container,
    Command.Settings.Node,
    Command.Settings.User
  ]

  @type public_t ::
          :run_automation
          | :clear_errors
          | Command.Cluster.t()
          | Command.Image.t()
          | Command.Container.t()
          | Command.Repository.t()
          | Command.Settings.Image.t()
          | Command.Settings.Container.t()
          | Command.Settings.Node.t()
          | Command.Settings.User.t()

  @type internal_t :: public_t() | Mutation.t() | Command.Workflow.t()
  @type effect ::
          {:work, Plan.t()}
          | {:state, State.t()}
          | {:state, State.t(), map()}
          | {:error, term()}

  @doc """
  Validate and normalize one public runtime command.

  Domain handlers own their command validation and execution together. Internal
  workflow commands remain private to `execute/2`.
  """
  @spec normalize(term()) :: {:ok, public_t()} | {:error, term()}
  def normalize(command) when command in [:run_automation, :clear_errors], do: {:ok, command}

  def normalize(%{__struct__: module} = command)
      when module in @typed_handlers,
      do: module.normalize(command)

  def normalize(_command), do: {:error, :invalid_command}

  @spec kind(public_t() | Mutation.t() | Command.Workflow.t()) :: atom()
  def kind(command) when is_atom(command), do: command

  def kind(%Mutation{}), do: :state_change
  def kind(%Command.Workflow{}), do: :workflow

  def kind(%{__struct__: module} = command)
      when module in @typed_handlers,
      do: module.kind(command)

  @spec execute(State.t(), internal_t()) :: effect()
  def execute(%State{} = state, %Mutation{} = mutation),
    do: MutationExecutor.execute(state, mutation)

  def execute(%State{} = state, %Command.Workflow{} = workflow),
    do: work(State.Jobs.build(state, workflow))

  def execute(%State{} = state, %{__struct__: module} = command)
      when module in @typed_handlers do
    state
    |> module.execute(command)
    |> normalize_effect()
  end

  def execute(%State{}, command),
    do: {:error, {:unsupported_command, command}}

  defp work(%Plan{} = plan), do: {:work, plan}
  defp work(work), do: {:work, Plan.new(work)}

  defp normalize_effect({:work, work}), do: work(work)
  defp normalize_effect({:state, %State{}} = result), do: result
  defp normalize_effect({:state, %State{}, result} = outcome) when is_map(result), do: outcome
  defp normalize_effect({:error, _reason} = result), do: result
end
