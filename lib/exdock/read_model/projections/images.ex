defmodule Exdock.ReadModel.Projections.Images do
  @moduledoc false

  @behaviour Exdock.ReadModel.Projection

  alias Exdock.Runtime.Projection

  @impl true
  def from_query(images), do: from_broadcast(images)

  @impl true
  def from_broadcast(images), do: %{images: Projection.images(images)}
end
