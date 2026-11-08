defmodule Exdock.Runtime.Command.Cluster do
  @moduledoc false

  @behaviour Exdock.Runtime.Command.Handler

  alias Exdock.Runtime.Command.Validation
  alias Exdock.Server.Jobs
  alias Exdock.Server.State

  @conditions [:normal, :hidden, :no]
  @actions [
    :refresh_cluster,
    :refresh_node,
    :fetch_registry_cluster,
    :fetch_registry_node
  ]

  defstruct [:action, :node, :condition]

  @type t :: %__MODULE__{
          action:
            :refresh_cluster
            | :refresh_node
            | :fetch_registry_cluster
            | :fetch_registry_node,
          node: String.t() | nil,
          condition: :normal | :hidden | :no | nil
        }

  @spec refresh_cluster(atom()) :: t()
  def refresh_cluster(condition \\ :normal),
    do: %__MODULE__{action: :refresh_cluster, condition: condition}

  @spec refresh_node(term(), atom()) :: t()
  def refresh_node(node, condition \\ :normal),
    do: %__MODULE__{action: :refresh_node, node: node, condition: condition}

  @spec fetch_registry_cluster() :: t()
  def fetch_registry_cluster,
    do: %__MODULE__{action: :fetch_registry_cluster}

  @spec fetch_registry_node(term()) :: t()
  def fetch_registry_node(node),
    do: %__MODULE__{action: :fetch_registry_node, node: node}

  @impl true
  def kind(%__MODULE__{action: action}) when action in @actions, do: action

  @impl true
  def normalize(%__MODULE__{action: :refresh_cluster, condition: condition} = command)
      when condition in @conditions,
      do: {:ok, command}

  def normalize(%__MODULE__{action: :refresh_node, condition: condition} = command)
      when condition in @conditions do
    with {:ok, node} <- Validation.runtime_node(command.node) do
      {:ok, %{command | node: node}}
    end
  end

  def normalize(%__MODULE__{action: :fetch_registry_cluster} = command),
    do: {:ok, command}

  def normalize(%__MODULE__{action: :fetch_registry_node} = command) do
    with {:ok, node} <- Validation.runtime_node(command.node) do
      {:ok, %{command | node: node}}
    end
  end

  def normalize(%__MODULE__{}), do: {:error, :invalid_command}

  @impl true
  def execute(
        %State{} = state,
        %__MODULE__{action: :refresh_cluster, condition: condition}
      ),
      do: work(Jobs.Client.Node.refresh_cluster(state, condition))

  def execute(
        %State{} = state,
        %__MODULE__{
          action: :refresh_node,
          node: node,
          condition: condition
        }
      ),
      do: work(Jobs.Client.Node.refresh_node(state, node, condition))

  def execute(%State{} = state, %__MODULE__{action: :fetch_registry_cluster}),
    do: work(Jobs.Local.Registry.fetch_cluster(state))

  def execute(
        %State{} = state,
        %__MODULE__{action: :fetch_registry_node, node: node}
      ),
      do: work(Jobs.Local.Registry.fetch_node(state, node))

  defp work(work), do: {:work, work}
end
