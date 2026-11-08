defmodule Exdock.ReadModel.Projections.Repositories do
  @moduledoc false

  @behaviour Exdock.ReadModel.Projection

  alias Exdock.Runtime.Projection

  @impl true
  def from_query(repositories), do: %{repositories: Projection.repositories(repositories)}

  @impl true
  def from_broadcast(repositories), do: %{repositories: repositories}
end
