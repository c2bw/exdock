defmodule Exdock.Server.Jobs.State.Continuations do
  @moduledoc "Stores named workflow continuations for queued job details."

  alias Exdock.Runtime.Command
  alias Exdock.Runtime.Command.Workflow

  defstruct entries: %{}

  @type continuation :: Workflow.t()
  @type t :: %__MODULE__{entries: %{String.t() => continuation()}}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec add(t(), String.t(), continuation() | nil) :: t()
  def add(%__MODULE__{} = state, _id, nil), do: state

  def add(%__MODULE__{entries: entries} = state, id, %Workflow{} = continuation)
      when is_binary(id) do
    %{state | entries: Map.put(entries, id, continuation)}
  end

  @type effect :: {:server_command, Command.internal_t()} | {:workflow_stopped, term()}

  @spec complete(t(), String.t(), term()) :: {t(), [effect()]}
  def complete(%__MODULE__{entries: entries} = state, id, error) when is_binary(id) do
    {continuation, entries} = Map.pop(entries, id)
    {%{state | entries: entries}, completion_effects(continuation, error)}
  end

  defp completion_effects(nil, _error), do: []

  defp completion_effects(%Workflow{} = workflow, nil),
    do: [{:server_command, workflow}]

  defp completion_effects(%Workflow{}, error),
    do: [{:workflow_stopped, error}]
end
