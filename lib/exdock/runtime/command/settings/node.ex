defmodule Exdock.Runtime.Command.Settings.Node do
  @moduledoc false

  @behaviour Exdock.Runtime.Command.Handler

  alias Exdock.Runtime.Command.MutationExecutor
  alias Exdock.Runtime.Command.Validation
  alias Exdock.Runtime.Mutation

  @action :change_node_setting

  defstruct action: @action, data: nil, mutation: nil

  @type t :: %__MODULE__{
          action: :change_node_setting,
          data: term(),
          mutation: Exdock.Runtime.Mutation.t() | nil
        }

  @spec node_setting(term(), atom(), term()) :: t()
  def node_setting(node, key, value),
    do: %__MODULE__{data: {node, key, value}}

  @impl true
  def kind(%__MODULE__{action: @action}), do: @action

  @impl true
  def normalize(
        %__MODULE__{
          action: @action,
          data: {node, key, value}
        } = command
      ) do
    with {:ok, node} <- Validation.runtime_node(node) do
      MutationExecutor.attach(command, Mutation.node_setting(node, key, value))
    end
  end

  def normalize(%__MODULE__{}), do: {:error, :invalid_command}

  @impl true
  defdelegate execute(state, command), to: MutationExecutor
end
