defmodule Exdock.ReadModel.Projections.Containers do
  @moduledoc false

  @behaviour Exdock.ReadModel.Projection

  alias Exdock.Runtime.Projection

  @impl true
  def from_query(containers), do: from_broadcast(containers)

  @impl true
  def from_broadcast(containers) do
    containers = Projection.containers(containers)

    %{
      containers: containers,
      containers_extended: Projection.containers_extended(containers)
    }
  end
end
