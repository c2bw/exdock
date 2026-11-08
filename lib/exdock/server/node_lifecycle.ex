defmodule Exdock.Server.NodeLifecycle do
  @moduledoc """
  Applies node connection transitions and delegates their explicit effects.
  """

  alias Exdock.NodeId
  alias Exdock.Server.NodeLifecycle.{Handler, Policy}
  alias Exdock.Server.State

  @spec reset(State.t(), module()) :: State.t()
  def reset(%State{} = state, handler \\ Handler) do
    state.cluster.storage
    |> State.Storage.Nodes.list()
    |> Enum.reduce(state, &disconnected(&2, &1, handler))
  end

  @spec connected(State.t(), String.t(), map(), module()) :: State.t()
  def connected(%State{} = state, node, metadata, handler \\ Handler)
      when is_binary(node) and is_map(metadata) and is_atom(handler) do
    node = NodeId.normalize!(node)

    {state, effects} = state |> State.nodeup(node, metadata) |> Policy.connected(node)
    :ok = handler.run(effects)
    state
  end

  @spec disconnected(State.t(), String.t(), module()) :: State.t()
  def disconnected(%State{} = state, node, handler \\ Handler)
      when is_binary(node) and is_atom(handler) do
    node = NodeId.normalize!(node)
    {state, effects} = state |> State.nodedown(node) |> Policy.disconnected(node)
    :ok = handler.run(effects)
    state
  end
end
