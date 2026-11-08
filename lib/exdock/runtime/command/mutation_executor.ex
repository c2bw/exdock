defmodule Exdock.Runtime.Command.MutationExecutor do
  @moduledoc false

  alias Exdock.Runtime.Mutation
  alias Exdock.Server.State

  @spec attach(struct(), {:ok, Mutation.t()} | {:error, term()}) :: {:ok, struct()} | {:error, term()}
  def attach(command, mutation_result) when is_struct(command) do
    with {:ok, %Mutation{} = mutation} <- mutation_result do
      {:ok, %{command | mutation: mutation}}
    end
  end

  @spec execute(State.t(), Mutation.t() | struct()) ::
          {:state, State.t(), map()} | {:error, term()}
  def execute(%State{} = state, %{mutation: %Mutation{} = mutation}), do: execute(state, mutation)

  def execute(%State{} = state, %Mutation{} = mutation) do
    case State.Change.commit_with_result(state, mutation) do
      {:ok, updated_state, operation_result} -> {:state, updated_state, operation_result}
      {:error, reason, %State{}} -> {:error, reason}
    end
  end
end
