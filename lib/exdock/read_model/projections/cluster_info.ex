defmodule Exdock.ReadModel.Projections.ClusterInfo do
  @moduledoc false

  @behaviour Exdock.ReadModel.Projection

  @impl true
  def from_query(cluster_info), do: %{cluster_info: cluster_info}

  @impl true
  def from_broadcast(cluster_info), do: %{cluster_info: cluster_info}
end
