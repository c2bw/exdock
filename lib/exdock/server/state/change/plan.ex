defmodule Exdock.Server.State.Change.Plan do
  @moduledoc """
  Prepared direct-domain work for a state change.

  Immediate plans contain an already reduced result. Persisted plans carry an
  inspectable domain operation whose executor owns both the durable write and
  projection of its result into an in-memory transition.
  """

  alias Exdock.Server.State
  alias Exdock.Server.State.Change.{Operation, Outcome}
  alias Exdock.Runtime.Mutation

  @type outcome :: Outcome.t() | {:error, term()}

  @enforce_keys [:kind]
  defstruct [:kind, :outcome, :operation]

  @type t :: %__MODULE__{
          kind: :immediate | :persisted,
          outcome: outcome() | nil,
          operation: Operation.t() | nil
        }

  @spec immediate(outcome()) :: t()
  def immediate(%Outcome{} = outcome), do: %__MODULE__{kind: :immediate, outcome: outcome}
  def immediate({:error, _reason} = outcome), do: %__MODULE__{kind: :immediate, outcome: outcome}

  @spec persisted(module(), State.t(), Exdock.Runtime.Mutation.t()) :: t()
  def persisted(executor, %State{} = state, %Mutation{} = mutation)
      when is_atom(executor),
      do: %__MODULE__{kind: :persisted, operation: Operation.new(executor, state, mutation)}

  @spec invalid_mutation_payload(Mutation.t()) :: t()
  def invalid_mutation_payload(%Mutation{domain: domain, action: action}) do
    immediate({:error, {:invalid_mutation_payload, domain, action}})
  end

  @spec execute(t()) :: outcome()
  def execute(%__MODULE__{kind: :immediate, outcome: outcome}), do: outcome

  def execute(%__MODULE__{kind: :persisted, operation: %Operation{} = operation}),
    do: Operation.execute(operation)

  @spec reduce(t()) :: outcome()
  def reduce(%__MODULE__{kind: :immediate, outcome: outcome}), do: outcome
  def reduce(%__MODULE__{kind: :persisted}), do: {:error, :persistence_execution_required}
end
