defmodule Exdock.Runtime.Command.Container do
  @moduledoc false

  @behaviour Exdock.Runtime.Command.Handler

  alias Exdock.Runtime.Command.Validation
  alias Exdock.Server.Jobs
  alias Exdock.Server.State

  @actions [
    :recreate_containers,
    :start_container,
    :stop_container,
    :restart_container,
    :fetch_container_logs
  ]

  defstruct [:action, :node, :name, :containers, :pull_image]

  @type t :: %__MODULE__{
          action:
            :recreate_containers
            | :start_container
            | :stop_container
            | :restart_container
            | :fetch_container_logs,
          node: String.t() | nil,
          name: String.t() | nil,
          containers: [{String.t(), String.t()}] | nil,
          pull_image: boolean() | nil
        }

  @spec recreate([{term(), String.t()}], boolean()) :: t()
  def recreate(containers, pull_image),
    do: %__MODULE__{
      action: :recreate_containers,
      containers: containers,
      pull_image: pull_image
    }

  @spec start(term(), String.t()) :: t()
  def start(node, name),
    do: action(:start_container, node, name)

  @spec stop(term(), String.t()) :: t()
  def stop(node, name),
    do: action(:stop_container, node, name)

  @spec restart(term(), String.t()) :: t()
  def restart(node, name),
    do: action(:restart_container, node, name)

  @spec logs(term(), String.t()) :: t()
  def logs(node, name),
    do: action(:fetch_container_logs, node, name)

  @impl true
  def kind(%__MODULE__{action: action}) when action in @actions, do: action

  @impl true
  def normalize(
        %__MODULE__{
          action: :recreate_containers,
          containers: containers,
          pull_image: pull_image
        } = command
      )
      when is_list(containers) and is_boolean(pull_image) do
    with {:ok, containers} <- normalize_container_refs(containers) do
      {:ok, %{command | containers: containers}}
    end
  end

  def normalize(%__MODULE__{action: action, name: name} = command)
      when action in [
             :start_container,
             :stop_container,
             :restart_container,
             :fetch_container_logs
           ] and is_binary(name) do
    with {:ok, node} <- Validation.runtime_node(command.node) do
      {:ok, %{command | node: node}}
    end
  end

  def normalize(%__MODULE__{}), do: {:error, :invalid_command}

  @impl true
  def execute(
        %State{} = state,
        %__MODULE__{
          action: :recreate_containers,
          containers: containers,
          pull_image: pull_image
        }
      ),
      do: work(Jobs.Client.Container.recreate(state, containers, pull_image))

  def execute(
        %State{} = state,
        %__MODULE__{action: :start_container, node: node, name: name}
      ),
      do: work(Jobs.Client.Container.start(state, node, name))

  def execute(
        %State{} = state,
        %__MODULE__{action: :stop_container, node: node, name: name}
      ),
      do: work(Jobs.Client.Container.stop(state, node, name))

  def execute(
        %State{} = state,
        %__MODULE__{action: :restart_container, node: node, name: name}
      ),
      do: work(Jobs.Client.Container.restart(state, node, name))

  def execute(
        %State{} = state,
        %__MODULE__{action: :fetch_container_logs, node: node, name: name}
      ),
      do: work(Jobs.Client.Container.logs(state, node, name))

  defp action(action, node, name),
    do: %__MODULE__{action: action, node: node, name: name}

  defp normalize_container_refs(containers) do
    Validation.map_all(containers, fn
      {node, name} when is_binary(name) ->
        with {:ok, node} <- Validation.runtime_node(node) do
          {:ok, {node, name}}
        end

      _invalid ->
        {:error, :invalid_container_reference}
    end)
  end

  defp work(work), do: {:work, work}
end
