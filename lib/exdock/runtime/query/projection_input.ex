defmodule Exdock.Runtime.Query.ProjectionInput do
  @moduledoc false

  alias Exdock.Server.State
  alias Exdock.Server.State.Storage

  @spec for(Exdock.ReadModel.Projections.key(), State.t()) :: term()
  def for(:nodes, %State{} = state) do
    %{
      nodes: Storage.Nodes.full_string_map(state),
      nodes_list: Storage.Nodes.ordered_list(state)
    }
  end

  def for(:containers, %State{} = state), do: Storage.Containers.full_string_map(state)
  def for(:images, %State{} = state), do: Storage.Images.full_string_map(state)
  def for(:repositories, %State{} = state), do: Storage.Repositories.list(state)
  def for(:cluster_info, %State{} = state), do: Storage.Cluster.info(state)
end
