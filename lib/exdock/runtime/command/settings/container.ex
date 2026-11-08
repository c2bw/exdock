defmodule Exdock.Runtime.Command.Settings.Container do
  @moduledoc false

  @behaviour Exdock.Runtime.Command.Handler

  alias Exdock.Runtime.Command.MutationExecutor
  alias Exdock.Runtime.Command.Validation
  alias Exdock.Runtime.Mutation

  @actions [
    :set_container_priority,
    :set_container_priorities,
    :set_container_auto_update
  ]

  defstruct [:action, :data, :mutation]

  @type t :: %__MODULE__{
          action:
            :set_container_priority
            | :set_container_priorities
            | :set_container_auto_update,
          data: term(),
          mutation: Exdock.Runtime.Mutation.t() | nil
        }

  @spec container_priority(term(), String.t(), integer()) :: t()
  def container_priority(node, name, priority),
    do: command(:set_container_priority, {node, name, priority})

  @spec container_priorities([{term(), String.t(), integer()}]) :: t()
  def container_priorities(priorities),
    do: command(:set_container_priorities, priorities)

  @spec container_auto_update(term(), String.t(), atom()) :: t()
  def container_auto_update(node, name, policy),
    do: command(:set_container_auto_update, {node, name, policy})

  @impl true
  def kind(%__MODULE__{action: action}) when action in @actions, do: action

  @impl true
  def normalize(
        %__MODULE__{
          action: :set_container_priority,
          data: {node, name, priority}
        } = command
      ) do
    with {:ok, node} <- Validation.runtime_node(node) do
      MutationExecutor.attach(command, Mutation.container_priority(node, name, priority))
    end
  end

  def normalize(
        %__MODULE__{
          action: :set_container_priorities,
          data: priorities
        } = command
      ) do
    with {:ok, priorities} <- normalize_priorities(priorities) do
      MutationExecutor.attach(command, Mutation.container_priorities(priorities))
    end
  end

  def normalize(
        %__MODULE__{
          action: :set_container_auto_update,
          data: {node, name, policy}
        } = command
      ) do
    with {:ok, node} <- Validation.runtime_node(node) do
      MutationExecutor.attach(command, Mutation.container_auto_update(node, name, policy))
    end
  end

  def normalize(%__MODULE__{}), do: {:error, :invalid_command}

  @impl true
  defdelegate execute(state, command), to: MutationExecutor

  defp command(action, data), do: %__MODULE__{action: action, data: data}

  defp normalize_priorities(priorities) when is_list(priorities) do
    Validation.map_all(priorities, fn
      {node, name, priority} ->
        with {:ok, node} <- Validation.runtime_node(node) do
          {:ok, {node, name, priority}}
        end

      invalid ->
        {:ok, invalid}
    end)
  end

  defp normalize_priorities(priorities), do: {:ok, priorities}
end
