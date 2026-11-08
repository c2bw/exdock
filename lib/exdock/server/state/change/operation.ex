defmodule Exdock.Server.State.Change.Operation do
  @moduledoc """
  Inspectable deferred work for a persisted domain mutation.

  The executor is a state-domain module implementing `execute_persisted/2`.
  Keeping the original state and normalized mutation in a struct makes queued
  work observable without running persistence during preparation.
  """

  alias Exdock.Runtime.Mutation
  alias Exdock.Server.State

  @enforce_keys [:executor, :state, :mutation]
  defstruct [:executor, :state, :mutation]

  @type t :: %__MODULE__{
          executor: module(),
          state: State.t(),
          mutation: Mutation.t()
        }

  @spec new(module(), State.t(), Mutation.t()) :: t()
  def new(executor, %State{} = state, %Mutation{} = mutation) when is_atom(executor) do
    %__MODULE__{executor: executor, state: state, mutation: mutation}
  end

  @spec execute(t()) :: term()
  def execute(%__MODULE__{executor: executor, state: state, mutation: mutation}) do
    executor.execute_persisted(state, mutation)
  end
end
